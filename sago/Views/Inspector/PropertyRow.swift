//
//  PropertyRow.swift
//  sago
//

import SwiftUI

/// A field name on the first line and a read-only text field with its value on the second.
struct PropertyRow: View {
    let key: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(key)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            // A constant binding keeps the field read-only while still allowing selection/copy.
            TextField(key, text: .constant(value))
                .textFieldStyle(.roundedBorder)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .labelsHidden()
        }
    }
}

#Preview {
    PropertyRow(key: "name", value: "Keanu Reeves")
        .padding()
        .frame(width: 280)
}
