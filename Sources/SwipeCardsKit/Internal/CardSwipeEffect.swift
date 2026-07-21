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
        switch index {
        case 0:
            // Только верхняя карта следит за пальцем — offset и угол живые, не анимируются
            // явно (withAnimation), они просто следуют за перетаскиванием кадр в кадр.
            let angle = Angle(degrees: Double(offset.x) / 20)
            content
                .offset(x: offset.x, y: offset.y)
                .rotationEffect(angle, anchor: .bottom)
                .zIndex(2)
        case 1, 2:
            // Карты позади стоят в фиксированной "отдыхающей" позе — никакой привязки
            // к прогрессу драга. Единственное движение — переход между этими двумя позами,
            // когда popItem() анимированно сдвигает стопку. Так на экране в любой момент
            // происходит ровно одно осмысленное движение, а не смесь offset+scale+fade.
            let scale: CGFloat = index == 1 ? 0.95 : 0.9
            let rotation: Double = index == 1 ? 9 : -9
            content
                .scaleEffect(scale)
                .rotationEffect(.degrees(rotation), anchor: .center)
                .zIndex(Double(2 - index))
        default:
            content
                .opacity(0)
        }
    }
}
