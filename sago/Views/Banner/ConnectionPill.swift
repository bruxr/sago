//
//  ConnectionPill.swift
//  sago
//

import SwiftUI

/// Center banner pill showing the current server, database and user.
struct ConnectionPill: View {
    let connection: ConnectionInfo

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.green)
                .frame(width: 7, height: 7)

            Text(connection.uri)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)

            separator

            Label(connection.database, systemImage: "cylinder.split.1x2")
                .labelStyle(.titleAndIcon)
                .lineLimit(1)

            separator

            Label(connection.user, systemImage: "person.crop.circle")
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
        }
        .font(.callout)
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .frame(minWidth: 280)
        .accessibilityElement(children: .combine)
    }

    private var separator: some View {
        Text("·")
            .foregroundStyle(.tertiary)
    }
}

#Preview {
    ConnectionPill(connection: PlaceholderData.connection)
        .padding()
}
