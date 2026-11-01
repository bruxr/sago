//
//  ShakeEffect.swift
//  sago
//

import SwiftUI

/// Horizontal shake, played once each time `shakes` increases by one.
struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat
    var amplitude: CGFloat = 8
    var oscillations: CGFloat = 3

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let offset = amplitude * sin(shakes * .pi * 2 * oscillations)
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}
