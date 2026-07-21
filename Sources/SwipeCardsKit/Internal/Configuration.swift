//
//  Configuration.swift
//  SwipeCardsKit
//
//  Created by Beka Demuradze on 04.05.25.
//

import SwiftUI

@MainActor
final class Configuration<Item: Identifiable> {
    var triggerThreshold: CGFloat = 150
    var minimumDistance: CGFloat = 20
    var animateOnYAxes: Bool = false
    var onSwipeEnd: ((Item, CardSwipeDirection) -> Void)?
    var onThresholdPassed: (() -> Void)?
    var onNoMoreCardsLeft: (() -> Void)?
    // Top card + 2 fanned behind it. A 4th, near-invisible slot used to fade/scale in
    // out of nowhere the instant it was promoted — dropping it removes that glitch outright.
    let visibleCount = 3
    let screenWidth = UIScreen.current?.bounds.width ?? 400
}
