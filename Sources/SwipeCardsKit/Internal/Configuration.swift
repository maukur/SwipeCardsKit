//
//  Configuration.swift
//  SwipeCardsKit
//
//  Created by Beka Demuradze on 04.05.25.
//

import SwiftUI

// Top card + 2 fanned behind it. A 4th, near-invisible slot used to fade/scale in
// out of nowhere the instant it was promoted — dropping it removes that glitch outright.
// CardSwipeEffect's slot cases and SwipeCardsView.stackAnimation(for:) are keyed to this
// same number — keep all three in sync if this ever changes.
let cardStackVisibleCount = 3

@MainActor
final class Configuration<Item: Identifiable> {
    var triggerThreshold: CGFloat = 150
    var minimumDistance: CGFloat = 20
    var animateOnYAxes: Bool = false
    var onSwipeEnd: ((Item, CardSwipeDirection) -> Void)?
    var onThresholdPassed: (() -> Void)?
    var onNoMoreCardsLeft: (() -> Void)?
    let visibleCount = cardStackVisibleCount
    // Not cached at app scope on purpose: Configuration is rebuilt fresh every render
    // (see CardSwipeView.configuration), so this naturally re-reads the current screen
    // instead of freezing whatever was available the first time a card view appeared.
    let screenWidth = UIScreen.current?.bounds.width ?? 400
}
