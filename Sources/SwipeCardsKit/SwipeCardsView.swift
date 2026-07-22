//
//  SwipeCardsView.swift
//  SwipeCardsKit
//
//  Created by Beka Demuradze on 27.04.25.
//

import SwiftUI

/// Что именно донесло карту до коммита — от этого зависит, какой физике должен
/// соответствовать вылет (см. flightAnimation(for:) в animatePoppedItem()).
private enum PoppedFlightKind {
    /// Программный свайп (кнопка да/нет) — скорость жеста отсутствует по определению.
    case button
    /// Обычный медленный драг, дошедший до порога сам, без проекции — торможение уже погашено.
    case distanceDrag
    /// Короткий, но быстрый флик — до порога довела не дистанция, а predictedEndTranslation.
    /// На iOS 17+ здесь есть реальная скорость жеста (pt/s) для полёта; на более старых —
    /// её взять неоткуда (DragGesture.Value.velocity появился только в iOS 17).
    case velocityDrag(CGFloat?)
}

public struct CardSwipeView<Item: Identifiable & Hashable, Content: View>: View {
    // Deliberately NOT @State: this is mutated only by the configure()/onXxx() builder
    // chain below, right after each fresh init — never from within the view's own logic.
    // @State persists across re-renders by identity, which would make it "sticky" to
    // whatever configure()/onSwipeEnd() happened to run on the very first render for this
    // view's identity — every later re-render constructs a new Configuration, calls the
    // builder methods on it, and SwiftUI would silently discard that instance in favor of
    // the first one, freezing closures/threshold values forever even if the caller passes
    // different ones later. A plain `let` just uses whatever this render's chain produced.
    private let configuration = Configuration<Item>()
    @State private var poppedItem: Item?
    @State private var poppedOffset: CGPoint = .zero
    @State private var poppedDirection: CardSwipeDirection = .idle
    @State private var lastDirection: CardSwipeDirection = .idle
    @State private var offset: CGPoint = .zero
    @State private var thresholdPassed = false
    // Guards the single poppedItem/poppedOffset slot: a second pop while one is still
    // flying off would overwrite that state and let the earlier pop's completion closure
    // clear the newer card mid-animation (and potentially double-fire onNoMoreCardsLeft).
    @State private var isPoppingOut = false

    // Три физически разных вылета: кнопка (нулевая скорость), драг, дошедший до порога
    // своим ходом (скорость уже погашена торможением), и драг, которому порог "дало" только
    // предсказанное конечное положение — в нём несём реальную скорость жеста дальше, в полёт.
    @State private var poppedFlightKind: PoppedFlightKind = .button

    // pre-iOS17 фолбэк в animatePoppedItem() ждёт через Task.sleep вместо completion-колбэка
    // withAnimation. Храним хендл и отменяем предыдущий перед стартом нового — без этого,
    // случись повторный вылет раньше срока, более старая задача могла бы отработать позже
    // и сбросить isPoppingOut/poppedItem уже после того, как новая карта отлетела и осела.
    @State private var flightTask: Task<Void, Never>?

    // popItem() mutates `items` itself (removeFirst), which would otherwise make the
    // onChange(of: items) reset below fire on every normal pop too. Set right before that
    // mutation, consumed (and cleared) by the first onChange it triggers.
    @State private var isInternalItemsMutation = false

    @Binding private var items: [Item]
    @Binding private var selectedItem: Item?
    @Binding private var popTrigger: CardSwipeDirection?
    private let content: (Item, _ progress: CGFloat, _ direction: CardSwipeDirection, _ index: Int) -> Content

    private var screenWidth: CGFloat {
        configuration.screenWidth
    }

    public init(
        items: Binding<[Item]>,
        selectedItem: Binding<Item?> = .constant(nil),
        popTrigger: Binding<CardSwipeDirection?> = .constant(nil),
        @ViewBuilder content: @escaping (Item, _ progress: CGFloat, _ direction: CardSwipeDirection, _ index: Int) -> Content
    ) {
        _items = items
        _selectedItem = selectedItem
        _popTrigger = popTrigger
        self.content = content
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: configuration.minimumDistance)
            .onChanged { value in
                onDragChanged(value)
            }
            .onEnded { value in
                let distance = abs(value.translation.width)
                // predictedEndTranslation — куда донесёт карту по инерции с текущей скоростью
                // (iOS 13+, платформенная модель проекции из WWDC18 "Designing Fluid
                // Interfaces"). Короткий быстрый флик долетает до порога через неё, даже не
                // покрыв 150pt дистанции сам — как и должно ощущаться "как в Тиндере".
                // distance >= 40 — защита от случайного дребезга: слишком короткое движение
                // не должно коммититься каким бы резким оно ни было спроецировано.
                let projected = abs(value.predictedEndTranslation.width)
                let committed = distance >= 40 && projected >= configuration.triggerThreshold

                guard committed, !items.isEmpty else {
                    // Небольшой перелёт мимо центра и обратно — карта отвечает как отпущенный
                    // физический объект, а не как сброс к дефолту.
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                        offset = .zero
                    }
                    return
                }

                if distance >= configuration.triggerThreshold {
                    // Дошла своим ходом — скорость к этому моменту уже погашена торможением.
                    popItem(flightKind: .distanceDrag)
                } else if #available(iOS 17.0, *) {
                    popItem(flightKind: .velocityDrag(value.velocity.width))
                } else {
                    popItem(flightKind: .velocityDrag(nil))
                }
            }
    }

    public var body: some View {
        ZStack {
            ForEach(Array(items.prefix(configuration.visibleCount).enumerated()), id: \.element.id) { index, item in
                let progress = index == 0 ? min(abs(offset.x) / configuration.triggerThreshold, 1) : 0

                content(item, progress, lastDirection, index)
                    .modifier(
                        CardSwipeEffect(
                            index: index,
                            offset: offset
                        )
                    )
                    // Явный transition — иначе новая карта, впервые попавшая в prefix(visibleCount),
                    // подхватывает дефолтный SwiftUI-переход и это конфликтует с анимацией ниже.
                    .transition(.opacity)
                    // У каждого слота своя кривая/задержка — карточки не переезжают все разом
                    // единым блоком, а подтягиваются друг за другом (см. stackAnimation ниже).
                    .animation(stackAnimation(for: index), value: index)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay { poppedCard }
        .gesture(swipeGesture)
        .onAppear {
            selectedItem = items.first
        }
        .onDisappear {
            // Pre-iOS17 fly-off fallback (see animatePoppedItem()) isn't tied to this view's
            // lifetime on its own — without this, a card mid-flight when the screen is
            // dismissed keeps sleeping in the background and fires onNoMoreCardsLeft? later
            // on a screen nobody's looking at.
            flightTask?.cancel()
        }
        .onChange(of: popTrigger ?? .idle) { newValue in
            guard newValue != .idle else { return }
            lastDirection = newValue
            popItem(flightKind: .button)
            popTrigger = nil
        }
        .onChange(of: items) { _ in
            // Fires both for our own items.removeFirst() in popItem() and for a caller
            // swapping in an entirely new deck (e.g. reloading the same screen after a
            // purchase). Only the latter should reset flight state — otherwise this would
            // cancel the very pop animation it just started.
            guard !isInternalItemsMutation else {
                isInternalItemsMutation = false
                return
            }
            flightTask?.cancel()
            isPoppingOut = false
            poppedItem = nil
            poppedOffset = .zero
            offset = .zero
            thresholdPassed = false
        }
    }

    @ViewBuilder
    var poppedCard: some View {
        if let poppedItem {
            content(poppedItem, min(abs(poppedOffset.x) / configuration.triggerThreshold, 1), poppedDirection, 0)
                .modifier(
                    CardSwipeEffect(
                        index: 0,
                        offset: poppedOffset
                    )
                )
                .id(poppedItem.id)
                .onAppear {
                    animatePoppedItem()
                }
        }
    }

    // Каскад стопки: фронтовая карта (новый index 0) реагирует первой и туже́ всего,
    // вторая (index 1) подтягивается ~60мс спустя спокойнее, а карта, только что попавшая
    // в видимое окно (index 2), просто проявляется фейдом ~95мс спустя — она уже в своей
    // целевой позе (масштаб/угол из CardSwipeEffect), крутить её незачем, она и так не видна
    // из-под двух карт впереди.
    private func stackAnimation(for index: Int) -> Animation? {
        switch index {
        case 0: .spring(response: 0.40, dampingFraction: 0.90)
        case 1: .spring(response: 0.42, dampingFraction: 1.0).delay(0.06)
        case 2: .easeOut(duration: 0.28).delay(0.095)
        default: nil
        }
    }

    func onDragChanged(_ value: DragGesture.Value) {
        let translation = value.translation.width
        let correction = correction(for: translation)
        let offsetX = translation + correction
        let offsetY = configuration.animateOnYAxes
            ? value.translation.height
            : 0
        offset = CGPoint(x: offsetX, y: offsetY)

        let newDirection = CardSwipeDirection(offset: offsetX)
        if lastDirection != newDirection {
            lastDirection = newDirection
        }

        let thresholdReached = abs(offsetX) >= configuration.triggerThreshold
        if thresholdReached != thresholdPassed {
            thresholdPassed = thresholdReached
            if thresholdReached {
                configuration.onThresholdPassed?()
            }
        }
    }

    func correction(for translation: CGFloat) -> CGFloat {
        if translation >= configuration.minimumDistance {
            -configuration.minimumDistance
        } else if translation <= -configuration.minimumDistance {
            configuration.minimumDistance
        } else {
            -translation
        }
    }

    // Кнопка стартует с нулевой скорости — чуть более длинная кривая с едва заметным bounce
    // компенсирует отсутствие исходного импульса без отдельной фазы разгона. Обычный драг,
    // дошедший своим ходом, тормозил уже во время самого драга — резче и без bounce. А флик,
    // которому порог дала только проекция (predictedEndTranslation), несёт свою реальную
    // скорость дальше, в вылет — на iOS 17+ по-настоящему (interpolatingSpring initialVelocity),
    // на более старых — коротким response без данных о скорости.
    private func flightAnimation(for kind: PoppedFlightKind) -> Animation {
        switch kind {
        case .button:
            return .spring(response: 0.38, dampingFraction: 0.95)
        case .distanceDrag:
            return .spring(response: 0.32, dampingFraction: 1.0)
        case let .velocityDrag(velocityX):
            if let velocityX, #available(iOS 17.0, *) {
                let normalized = min(max(abs(velocityX) / screenWidth, 0), 30)
                return .interpolatingSpring(duration: 0.28, bounce: 0, initialVelocity: normalized)
            }
            return .spring(response: 0.26, dampingFraction: 1.0)
        }
    }

    func animatePoppedItem() {
        let multiplier: CGFloat = poppedDirection == .left ? -1 : 1
        let flightAnimation = flightAnimation(for: poppedFlightKind)

        if #available(iOS 17.0, *) {
            withAnimation(flightAnimation) {
                poppedOffset.x += (screenWidth * multiplier)
            } completion: {
                self.poppedItem = nil
                self.poppedOffset = .zero
                self.isPoppingOut = false

                if items.isEmpty {
                    configuration.onNoMoreCardsLeft?()
                }
            }
        } else {
            withAnimation(flightAnimation) {
                poppedOffset.x += (screenWidth * multiplier)
            }

            flightTask?.cancel()
            // @MainActor обязателен явно: изоляция замыкания Task{} — компайл-тайм свойство
            // места объявления, а не потока вызова. animatePoppedItem() — обычный instance-метод,
            // не MainActor-инференсный `body` из View. Без явной пометки после `await Task.sleep`
            // код мог бы резюмироваться на потоке кооперативного пула, а не на main.
            flightTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: (1 * NSEC_PER_SEC) / 2)
                guard !Task.isCancelled else { return }

                self.poppedItem = nil
                self.isPoppingOut = false

                if items.isEmpty {
                    configuration.onNoMoreCardsLeft?()
                }
            }
        }
    }

    // Свайп по кнопке и настоящий драг оба должны надёжно сообщать об исходе — раньше
    // popTrigger-путь звал popItem(notifyCaller: false), и если isPoppingOut блокировал
    // повторный вызов (карта ещё летит), внешний код мог решить, что своп случился,
    // хотя колода не сдвинулась. Теперь onSwipeEnd зовётся всегда, когда поп реально прошёл.
    private func popItem(flightKind: PoppedFlightKind) {
        guard !items.isEmpty, !isPoppingOut else { return }
        isPoppingOut = true
        poppedOffset = offset
        poppedDirection = lastDirection
        poppedFlightKind = flightKind
        isInternalItemsMutation = true
        // Существующие слоты (лидер/второй) анимируются каждый своей кривой через
        // .animation(value: index) на ForEach-строке — она перебивает любую ambient-анимацию
        // для этих значений. А вот у карты, только что попавшей в видимое окно (третий слот),
        // до этого момента не было ни строки, ни .animation(value:) — .transition(.opacity)
        // сработает только если сама вставка идёт внутри анимированной транзакции. Этот
        // withAnimation — как раз для неё; на уже существующие слоты он не влияет.
        withAnimation(.easeOut(duration: 0.28)) {
            poppedItem = items.removeFirst()
            selectedItem = items.first
            offset = .zero
        }
        if let poppedItem {
            configuration.onSwipeEnd?(poppedItem, lastDirection)
        }
    }
}

public extension CardSwipeView {
    func configure(
        threshold: CGFloat,
        minimumDistance: CGFloat,
        animateOnYAxes: Bool
    ) -> CardSwipeView {
        configuration.triggerThreshold = threshold
        configuration.minimumDistance = minimumDistance
        configuration.animateOnYAxes = animateOnYAxes
        return self
    }

    func onSwipeEnd(_ newValue: @escaping (Item, CardSwipeDirection) -> Void) -> CardSwipeView {
        configuration.onSwipeEnd = newValue
        return self
    }

    func onNoMoreCardsLeft(_ newValue: @escaping () -> Void) -> CardSwipeView {
        configuration.onNoMoreCardsLeft = newValue
        return self
    }

    func onThresholdPassed(_ newValue: @escaping () -> Void) -> CardSwipeView {
        configuration.onThresholdPassed = newValue
        return self
    }
}
