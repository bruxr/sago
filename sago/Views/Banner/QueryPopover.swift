//
//  QueryPopover.swift
//  sago
//

import SwiftUI

/// Popover for composing and sending a cypher query.
struct QueryPopover: View {
    let connection: ConnectionInfo
    let onRun: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = AttributedString()
    @State private var selection = AttributedTextSelection()
    @FocusState private var isEditorFocused: Bool

    private var plainQuery: String {
        String(query.characters)
    }

    private var trimmedQuery: String {
        plainQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                if query.characters.isEmpty {
                    Text("Enter a Cypher query…")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 1)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $query, selection: $selection)
                    .scrollContentBackground(.hidden)
                    .focused($isEditorFocused)
                    .autocorrectionDisabled()
                    // Only colors are kept, so pasted styling is dropped.
                    .attributedTextFormattingDefinition(CypherHighlighter.EditorScope.self)
                    .onChange(of: plainQuery) {
                        // Recolor without touching the characters, keeping the selection in place.
                        query.transform(updating: &selection) { CypherHighlighter.highlight(&$0) }
                    }
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
                    onRun(trimmedQuery)
                    query = AttributedString()
                    selection = AttributedTextSelection()
                    dismiss()
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
    QueryPopover(connection: PlaceholderData.connection, onRun: { _ in })
}
