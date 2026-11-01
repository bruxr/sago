//
//  QueryPopover.swift
//  sago
//

import SwiftUI

/// Popover for composing and sending a cypher query.
struct QueryPopover: View {
    let connection: ConnectionInfo

    @State private var query = ""
    @FocusState private var isEditorFocused: Bool

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                if query.isEmpty {
                    Text("Enter a Cypher query…")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 1)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $query)
                    .scrollContentBackground(.hidden)
                    .focused($isEditorFocused)
                    .autocorrectionDisabled()
            }
            .font(.system(.body, design: .monospaced))
            .frame(minHeight: 90)

            HStack(spacing: 8) {
                Label(connection.database, systemImage: "cylinder.split.1x2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: .capsule)

                Spacer()

                Button {
                    // TODO: Send query to the server.
                } label: {
                    Image(systemName: "arrow.up")
                        .fontWeight(.semibold)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .disabled(trimmedQuery.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityLabel("Run Query")
            }
        }
        .padding(14)
        .frame(width: 440)
        .onAppear { isEditorFocused = true }
    }
}

#Preview {
    QueryPopover(connection: PlaceholderData.connection)
}
