//
//  QueryRecord.swift
//  sago
//

import Foundation
import SwiftData

/// How a finished query went.
enum QueryStatus: String, Codable {
    case succeeded
    /// Succeeded but returned no rows and changed nothing.
    case empty
}

/// A cypher query previously sent to a server, kept across launches.
@Model
final class QueryRecord {
    /// Number of queries kept (and listed) per server.
    static let historyLimit = 100

    var cypher: String
    var date: Date
    /// The connection uri the query was sent to.
    var server: String
    var statusRaw: String

    var status: QueryStatus {
        QueryStatus(rawValue: statusRaw) ?? .empty
    }

    init(cypher: String, date: Date = .now, server: String, status: QueryStatus) {
        self.cypher = cypher
        self.date = date
        self.server = server
        self.statusRaw = status.rawValue
    }

    /// The server's most recent queries first, limited to `historyLimit`.
    static func history(server: String) -> FetchDescriptor<QueryRecord> {
        var descriptor = FetchDescriptor<QueryRecord>(
            predicate: #Predicate { $0.server == server },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = historyLimit
        return descriptor
    }

    /// Records a successful query. Repeating the server's latest query updates that entry instead of adding one.
    static func record(
        _ cypher: String, server: String, status: QueryStatus, in context: ModelContext
    ) throws {
        var latest = history(server: server)
        latest.fetchLimit = 1
        if let record = try context.fetch(latest).first, record.cypher == cypher {
            record.date = .now
            record.statusRaw = status.rawValue
        } else {
            context.insert(QueryRecord(cypher: cypher, server: server, status: status))
            try prune(server: server, in: context)
        }
    }

    /// Deletes the server's queries beyond the `historyLimit` most recent.
    static func prune(server: String, in context: ModelContext) throws {
        var descriptor = history(server: server)
        descriptor.fetchLimit = nil
        // `fetchOffset` is ignored without a `fetchLimit`, so skip the kept records here instead.
        for record in try context.fetch(descriptor).dropFirst(historyLimit) {
            context.delete(record)
        }
    }
}
