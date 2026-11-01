//
//  FloatingPanel.swift
//  sago
//

import SwiftUI

/// A glass card that floats above the graph canvas.
struct FloatingPanel<Content: View>: View {
    let width: CGFloat
    @ViewBuilder let content: Content

    static var cornerRadius: CGFloat { 18 }

    var body: some View {
        content
            .frame(width: width)
            .frame(maxHeight: .infinity, alignment: .top)
            .clipShape(.rect(cornerRadius: Self.cornerRadius))
            .glassEffect(.regular, in: .rect(cornerRadius: Self.cornerRadius))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}
