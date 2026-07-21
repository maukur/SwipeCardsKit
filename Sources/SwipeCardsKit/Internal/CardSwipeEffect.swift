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
    let triggerThreshold: CGFloat

    func body(content: Content) -> some View {
        switch index {
        case 0:
            let angle = Angle(degrees: Double(offset.x) / 20)
            content
                .offset(x: offset.x, y: offset.y)
                .rotationEffect(angle, anchor: .bottom)
                .zIndex(4)
        case 1:
            // Без offset(y:) — уменьшенная карта центрирована и выглядывает
            // одинаковой полоской и сверху, и снизу, а не только из-под низа.
            let progress = min(abs(offset.x) / triggerThreshold, 1)
            content
                .scaleEffect(CGFloat(0.95 + progress * 0.05))
                .rotationEffect(.degrees(9 * Double(1 - progress)), anchor: .center)
                .zIndex(3)
        case 2:
            let progress = min(abs(offset.x) / triggerThreshold, 1)
            content
                .scaleEffect(CGFloat(0.9 + progress * 0.05))
                .rotationEffect(.degrees(-9 * Double(1 - progress)), anchor: .center)
                .zIndex(2)
        case 3:
            let progress = min(abs(offset.x) / triggerThreshold, 1)
            content
                .opacity(progress)
                .scaleEffect(CGFloat(0.85 + progress * 0.05))
                .zIndex(1)
        default:
            content
                .opacity(0)
        }
    }
}
