//
//  RecentQueriesView.swift
//  sago
//

import SwiftUI

/// Left panel listing recently sent cypher queries.
struct RecentQueriesView: View {
    let queries: [RecentQuery]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent Queries")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 6)

            // ScrollView instead of List so row insets match the title exactly on both platforms.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(queries) { query in
                        Button {
                            // TODO: Send and run the query against the server.
                        } label: {
                            RecentQueryRow(query: query)
                        }
                        .buttonStyle(.plain)

                        if query.id != queries.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }
}

private struct RecentQueryRow: View {
    let query: RecentQuery

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(query.date, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(query.cypher)
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

#Preview {
    RecentQueriesView(queries: PlaceholderData.recentQueries)
        .frame(width: 260, height: 400)
}
