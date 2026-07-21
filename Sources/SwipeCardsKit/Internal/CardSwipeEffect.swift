//
//  CardSwipeEffect.swift
//  SwipeCardsKit
//
//  Created by Beka Demuradze on 04.05.25.
//

import SwiftUI

struct CardSwipeEffect: ViewModifier {
    let index: Int
    let offset: CGPoint

    func body(content: Content) -> some View {
        // Один и тот же набор модификаторов для всех слотов — меняются только ЗНАЧЕНИЯ по
        // index, а не сама структура вьюхи. Раньше это был switch с разными веткам (case 0:
        // offset+rotation(anchor:.bottom); case 1/2: scale+rotation(anchor:.center)) —
        // структурно разные типы вьюх, между которыми SwiftUI не интерполирует geometry,
        // а делает structural swap (снять старую ветку/вставить новую, аниморуется только
        // сам transition). Поэтому повышение карты (index 1→0) не "доезжало" одним плавным
        // движением, а перескакивало между двумя статичными позами. Единая цепочка даёт
        // персистентные _ScaleEffect/_RotationEffect/_OffsetEffect узлы — SwiftUI реально
        // едет пружиной от позы "карта позади" к позе "верхняя карта" как одно жёсткое тело.
        //
        // anchor тоже должен быть одним и тем же значением везде — сам anchor не анимируется
        // (не часть animatableData), так что isTop ? .bottom : .center дал бы скачок пивота
        // в первый же кадр перехода. .bottom — то, что уже было у верхней карты при драге.
        let isTop = index == 0
        let restScale: CGFloat = index == 1 ? 0.95 : 0.9
        let restRotation: Double = index == 1 ? 9 : -9

        let scale: CGFloat = isTop ? 1.0 : restScale
        let rotation: Double = isTop ? Double(offset.x) / 20 : restRotation
        let dx: CGFloat = isTop ? offset.x : 0
        let dy: CGFloat = isTop ? offset.y : 0

        content
            .scaleEffect(scale)
            .rotationEffect(.degrees(rotation), anchor: .bottom)
            .offset(x: dx, y: dy)
            .opacity(index >= 3 ? 0 : 1)
            .zIndex(Double(3 - index))
    }
}
