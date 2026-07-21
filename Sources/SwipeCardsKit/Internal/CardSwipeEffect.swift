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
            let progress = min(abs(offset.x) / triggerThreshold, 1)
            content
                .offset(y: CGFloat((1 - progress) * 50))
                .scaleEffect(CGFloat(0.9 + progress * 0.1))
                .rotationEffect(.degrees(15 * Double(1 - progress)), anchor: .bottom)
                .zIndex(3)
        case 2:
            let progress = min(abs(offset.x) / triggerThreshold, 1)
            content
                .offset(y: CGFloat(110 - progress * 60))
                .scaleEffect(CGFloat(0.8 + progress * 0.1))
                .rotationEffect(.degrees(-15 * Double(1 - progress)), anchor: .bottom)
                .zIndex(2)
        case 3:
            let progress = min(abs(offset.x) / triggerThreshold, 1)
            content
                .opacity(progress)
                .offset(y: CGFloat(180 - progress * 70))
                .scaleEffect(CGFloat(0.7 + progress * 0.1))
                .zIndex(1)
        default:
            content
                .opacity(0)
        }
    }
}
