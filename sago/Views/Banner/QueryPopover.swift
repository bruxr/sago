//
//  QueryPopover.swift
//  sago
//

import SwiftUI

/// Popover for composing and sending a cypher query.
struct QueryPopover: View {
    let connection: ConnectionInfo
    /// Whether a query is running; the popover can't be run again or closed meanwhile.
    let isRunning: Bool
    /// Runs the query, returning the error message if it failed.
    let onRun: (String) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var query = AttributedString()
    @State private var selection = AttributedTextSelection()
    @State private var errorMessage: String?
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
                        errorMessage = nil
                    }
            }
            .font(.system(.body, design: .monospaced))
            .frame(minHeight: 90)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            HStack(spacing: 8) {
                Label(connection.database, systemImage: "cylinder.split.1x2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: .capsule)

                Spacer()

                Button {
                    Task { await run() }
                } label: {
                    Group {
                        if isRunning {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.up")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .disabled(trimmedQuery.isEmpty || isRunning)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityLabel("Run Query")
            }
        }
        .padding(14)
        .frame(width: 440)
        .interactiveDismissDisabled(isRunning)
        .onAppear { isEditorFocused = true }
    }

    /// Runs the query; closes on success, otherwise keeps it for editing and shows the error.
    private func run() async {
        errorMessage = nil
        if let message = await onRun(trimmedQuery) {
            errorMessage = message
        } else {
            query = AttributedString()
            selection = AttributedTextSelection()
            dismiss()
        }
    }
}

#Preview {
    QueryPopover(connection: PlaceholderData.connection, isRunning: false, onRun: { _ in nil })
}
