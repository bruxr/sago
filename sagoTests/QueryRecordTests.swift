//
//  QueryRecordTests.swift
//  sagoTests
//

import Foundation
import SwiftData
import Testing
@testable import sago

@MainActor
struct QueryRecordTests {
    @Test func prunesOldestBeyondLimitPerServer() throws {
        let container = try ModelContainer(for: QueryRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let start = Date(timeIntervalSince1970: 0)
        for index in 0..<(QueryRecord.historyLimit + 5) {
            context.insert(QueryRecord(cypher: "A \(index)", date: start.addingTimeInterval(Double(index)), server: "a", status: .succeeded))
        }
        for index in 0..<3 {
            context.insert(QueryRecord(cypher: "B \(index)", date: start, server: "b", status: .empty))
        }

        try QueryRecord.prune(server: "a", in: context)

        let a = try context.fetch(QueryRecord.history(server: "a"))
        #expect(try context.fetchCount(FetchDescriptor<QueryRecord>(predicate: #Predicate { $0.server == "a" })) == QueryRecord.historyLimit)
        #expect(a.first?.cypher == "A \(QueryRecord.historyLimit + 4)")
        #expect(a.last?.cypher == "A 5")
        #expect(try context.fetchCount(FetchDescriptor<QueryRecord>(predicate: #Predicate { $0.server == "b" })) == 3)
    }

    @Test func repeatingLatestQueryUpdatesIt() throws {
        let container = try ModelContainer(for: QueryRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext

        try QueryRecord.record("MATCH (n) RETURN n", server: "a", status: .succeeded, in: context)
        try QueryRecord.record("MATCH (n) RETURN n", server: "a", status: .empty, in: context)
        #expect(try context.fetch(QueryRecord.history(server: "a")).map(\.status) == [.empty])

        // Only the latest entry is merged; an older duplicate is added again.
        try QueryRecord.record("RETURN 1", server: "a", status: .succeeded, in: context)
        try QueryRecord.record("MATCH (n) RETURN n", server: "a", status: .empty, in: context)
        #expect(try context.fetch(QueryRecord.history(server: "a")).map(\.cypher) == ["MATCH (n) RETURN n", "RETURN 1", "MATCH (n) RETURN n"])
    }
}
