//
//  SwipeCardsView.swift
//  SwipeCardsKit
//
//  Created by Beka Demuradze on 27.04.25.
//

import SwiftUI

public struct CardSwipeView<Item: Identifiable & Hashable, Content: View>: View {
    @State private var configuration = Configuration<Item>()
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

    // Настоящий драг уже несёт скорость жеста — улёт мягче/резче, чем у кнопки,
    // у которой скорость всегда нулевая. animatePoppedItem() выбирает кривую по этому флагу.
    @State private var poppedViaDrag = true

    // pre-iOS17 фолбэк в animatePoppedItem() ждёт через Task.sleep вместо completion-колбэка
    // withAnimation. Храним хендл и отменяем предыдущий перед стартом нового — без этого,
    // случись повторный вылет раньше срока, более старая задача могла бы отработать позже
    // и сбросить isPoppingOut/poppedItem уже после того, как новая карта отлетела и осела.
    @State private var flightTask: Task<Void, Never>?

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
                if abs(value.translation.width) < configuration.triggerThreshold {
                    // Небольшой перелёт мимо центра и обратно — карта отвечает как отпущенный
                    // физический объект, а не как сброс к дефолту.
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                        offset = .zero
                    }
                } else if !items.isEmpty {
                    popItem(triggeredByDrag: true)
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
        .onChange(of: popTrigger ?? .idle) { newValue in
            guard newValue != .idle else { return }
            lastDirection = newValue
            popItem(triggeredByDrag: false)
            popTrigger = nil
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

    func animatePoppedItem() {
        let multiplier: CGFloat = poppedDirection == .left ? -1 : 1
        // Драг уже несёт скорость жеста — чуть более резкий, некружащий вылет. Кнопка
        // стартует с нулевой скорости, поэтому даём кривой чуть больше времени и лёгкий
        // bounce — это компенсирует отсутствие исходного импульса без отдельной фазы разгона.
        let flightAnimation: Animation = poppedViaDrag
            ? .spring(response: 0.32, dampingFraction: 1.0)
            : .spring(response: 0.38, dampingFraction: 0.95)

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
    // withAnimation вокруг сдвига массива больше не нужен — каждый слот стопки анимирует
    // свой переход сам через .animation(value: index) на самой ForEach-строке (см. body).
    func popItem(triggeredByDrag: Bool) {
        guard !items.isEmpty, !isPoppingOut else { return }
        isPoppingOut = true
        poppedOffset = offset
        poppedDirection = lastDirection
        poppedViaDrag = triggeredByDrag
        poppedItem = items.removeFirst()
        selectedItem = items.first
        offset = .zero
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
