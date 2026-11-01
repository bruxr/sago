//
//  RecentQueriesView.swift
//  sago
//

import SwiftData
import SwiftUI

/// Left panel listing the queries recently sent to the current server.
struct RecentQueriesView: View {
    /// The query in progress, shown above the history.
    let runningQuery: String?
    /// Runs a query again; ignored while another one is running.
    let onRun: (String) -> Void

    @Query private var records: [QueryRecord]
    /// A write or delete query awaiting confirmation before it runs.
    @State private var pendingQuery: PendingQuery?

    init(server: String, runningQuery: String?, onRun: @escaping (String) -> Void) {
        self.runningQuery = runningQuery
        self.onRun = onRun
        _records = Query(QueryRecord.history(server: server))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent Queries")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 6)

            if records.isEmpty && runningQuery == nil {
                ContentUnavailableView {
                    Label("No Recent Queries", systemImage: "chevron.left.forwardslash.chevron.right")
                } description: {
                    Text("Queries you run on this server appear here.")
                }
                .frame(maxHeight: .infinity)
            } else {
                list
            }
        }
    }

    /// The history, minus the latest entry while it is the query being re-run (it shows as the running row).
    private var visibleRecords: ArraySlice<QueryRecord> {
        if let runningQuery, records.first?.cypher == runningQuery {
            records.dropFirst()
        } else {
            records[...]
        }
    }

    // ScrollView instead of List so row insets match the title exactly on both platforms.
    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let runningQuery {
                    RecentQueryRow(cypher: runningQuery, status: nil, date: nil)
                    if !visibleRecords.isEmpty {
                        Divider()
                    }
                }

                ForEach(visibleRecords) { record in
                    Button {
                        guard runningQuery == nil else { return }
                        let effect = CypherHighlighter.effect(of: record.cypher)
                        if effect == .read {
                            onRun(record.cypher)
                        } else {
                            pendingQuery = PendingQuery(cypher: record.cypher, effect: effect)
                        }
                    } label: {
                        RecentQueryRow(cypher: record.cypher, status: record.status, date: record.date)
                    }
                    .buttonStyle(.plain)

                    if record.id != visibleRecords.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .alert(
            pendingQuery?.title ?? "",
            isPresented: Binding(get: { pendingQuery != nil }, set: { if !$0 { pendingQuery = nil } }),
            presenting: pendingQuery
        ) { query in
            Button("Run Query", role: query.effect == .write ? nil : .destructive) {
                onRun(query.cypher)
            }
            Button("Cancel", role: .cancel) {}
        } message: { query in
            Text(query.message)
        }
    }
}

/// A query that changes data, held while the user confirms running it.
private struct PendingQuery {
    let cypher: String
    let effect: CypherHighlighter.Effect

    var title: String {
        switch effect {
        case .delete: "Run Destructive Query?"
        case .procedure: "Call Stored Procedure?"
        case .write, .read: "Run Write Query?"
        }
    }

    var message: String {
        switch effect {
        case .delete: "This query will delete or remove data. This can't be undone."
        case .procedure: "This query will call a stored procedure, which might cause data loss. Continue?"
        case .write, .read: "This query will create new nodes or relationships, or update existing ones."
        }
    }
}

private struct RecentQueryRow: View {
    let cypher: String
    /// `nil` while the query is running.
    let status: QueryStatus?
    let date: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                QueryStatusIndicator(status: status)
                Group {
                    if let date {
                        Text(date, format: .relative(presentation: .named))
                    } else {
                        Text("Running…")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Text(CypherHighlighter.highlighted(cypher))
                .font(.system(.callout, design: .monospaced))
                .lineLimit(3)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .contentShape(.rect)
    }
}

/// Green or amber dot for a finished query; a spinner while it runs.
private struct QueryStatusIndicator: View {
    let status: QueryStatus?

    var body: some View {
        Group {
            if let status {
                Circle()
                    .fill(color(for: status))
                    .frame(width: 7, height: 7)
            } else {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .frame(width: 12, height: 12)
        .accessibilityLabel(label)
    }

    private func color(for status: QueryStatus) -> Color {
        switch status {
        case .succeeded: .green
        case .empty: .orange
        }
    }

    private var label: String {
        switch status {
        case .succeeded: "Succeeded"
        case .empty: "No results"
        case nil: "Running"
        }
    }
}

#Preview {
    RecentQueriesView(server: PlaceholderData.connection.uri, runningQuery: "MATCH (n) RETURN n LIMIT 10", onRun: { _ in })
        .frame(width: 260, height: 400)
        .modelContainer(PlaceholderData.previewContainer)
}

#Preview("Empty") {
    RecentQueriesView(server: "neo4j://empty", runningQuery: nil, onRun: { _ in })
        .frame(width: 260, height: 400)
        .modelContainer(PlaceholderData.previewContainer)
}
