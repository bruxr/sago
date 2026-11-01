//
//  PlaceholderData.swift
//  sago
//

import Foundation
import SwiftData

/// Static sample data used until the app talks to a real server.
enum PlaceholderData {
    static let connection = ConnectionInfo(
        uri: "neo4j://localhost:7687",
        database: "neo4j",
        user: "neo4j"
    )

    /// In-memory store seeded with sample query history for `connection`.
    @MainActor static let previewContainer: ModelContainer = {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: QueryRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        } catch {
            fatalError("Could not create preview ModelContainer: \(error)")
        }
        let now = Date()
        let server = connection.uri
        let records = [
            QueryRecord(cypher: "MATCH (p:Person)-[r]->(m:Movie) RETURN p, r, m LIMIT 25", date: now.addingTimeInterval(-45), server: server, status: .succeeded),
            QueryRecord(cypher: "MATCH (m:Movie {title: 'The Matrix'})<-[:ACTED_IN]-(a) RETURN m, a", date: now.addingTimeInterval(-60 * 12), server: server, status: .empty),
            QueryRecord(cypher: "MATCH (n) RETURN count(n)", date: now.addingTimeInterval(-60 * 60 * 26), server: server, status: .succeeded),
            QueryRecord(cypher: "MATCH (d:Person)-[:DIRECTED]->(m:Movie) RETURN d.name, collect(m.title) AS movies", date: now.addingTimeInterval(-60 * 60 * 24 * 3), server: server, status: .succeeded),
            QueryRecord(cypher: "CREATE INDEX person_name IF NOT EXISTS FOR (p:Person) ON (p.name)", date: now.addingTimeInterval(-60 * 60 * 24 * 9), server: server, status: .succeeded),
        ]
        for record in records { container.mainContext.insert(record) }
        return container
    }()

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components) ?? .now
    }

    private static func person(_ id: Int, uuid: String, name: String, born: Int, updated: Date, labels: [String] = ["Person"]) -> GraphNode {
        GraphNode(id: id, labels: labels, properties: [
            "id": .string(uuid),
            "name": .string(name),
            "born": .int(born),
            "updatedAt": .date(updated),
        ])
    }

    private static func movie(_ id: Int, uuid: String, title: String, released: Int, tagline: String, genres: [String], labels: [String] = ["Movie"]) -> GraphNode {
        GraphNode(id: id, labels: labels, properties: [
            "id": .string(uuid),
            "title": .string(title),
            "released": .int(released),
            "tagline": .string(tagline),
            "genres": .list(genres.map { .string($0) }),
            "createdAt": .date(date(2024, 3, 14, 9, 30)),
        ])
    }

    static let nodes: [GraphNode] = [
        movie(0, uuid: "m-7f3a", title: "The Matrix", released: 1999, tagline: "Welcome to the Real World", genres: ["Sci-Fi", "Action"],
              labels: ["Movie", "Franchise"]),
        movie(1, uuid: "m-1b9c", title: "The Matrix Reloaded", released: 2003, tagline: "Free your mind", genres: ["Sci-Fi", "Action"]),
        movie(2, uuid: "m-44d0", title: "John Wick", released: 2014, tagline: "Don't set him off", genres: ["Action", "Thriller"]),
        movie(3, uuid: "m-a2e1", title: "Cloud Atlas", released: 2012, tagline: "Everything is connected", genres: ["Drama", "Sci-Fi"],
              labels: ["Movie", "Adaptation", "Ensemble"]),
        person(10, uuid: "p-0001", name: "Keanu Reeves", born: 1964, updated: date(2025, 6, 2, 14, 5),
               labels: ["Person", "Actor", "Producer"]),
        person(11, uuid: "p-0002", name: "Carrie-Anne Moss", born: 1967, updated: date(2025, 1, 20, 8, 45),
               labels: ["Person", "Actor"]),
        person(12, uuid: "p-0003", name: "Laurence Fishburne", born: 1961, updated: date(2024, 11, 11, 17, 0)),
        person(13, uuid: "p-0004", name: "Hugo Weaving", born: 1960, updated: date(2024, 9, 3, 10, 15)),
        person(14, uuid: "p-0005", name: "Lana Wachowski", born: 1965, updated: date(2025, 2, 28, 12, 0),
               labels: ["Person", "Director", "Writer", "Producer", "Screenwriter"]),
        person(15, uuid: "p-0006", name: "Lilly Wachowski", born: 1967, updated: date(2025, 2, 28, 12, 1),
               labels: ["Person", "Director", "Writer", "Producer"]),
        person(16, uuid: "p-0007", name: "Tom Hanks", born: 1956, updated: date(2025, 7, 19, 22, 30),
               labels: ["Person", "Actor", "Producer", "Director"]),
        person(17, uuid: "p-0008", name: "Chad Stahelski", born: 1968, updated: date(2024, 12, 24, 6, 50),
               labels: ["Person", "Director", "Stuntman"]),
    ]

    static let relationships: [GraphRelationship] = {
        let pairs: [(String, Int, Int)] = [
            ("ACTED_IN", 10, 0), ("ACTED_IN", 11, 0), ("ACTED_IN", 12, 0), ("ACTED_IN", 13, 0),
            ("ACTED_IN", 10, 1), ("ACTED_IN", 11, 1), ("ACTED_IN", 12, 1), ("ACTED_IN", 13, 1),
            ("ACTED_IN", 10, 2), ("ACTED_IN", 16, 3), ("ACTED_IN", 13, 3),
            ("DIRECTED", 14, 0), ("DIRECTED", 15, 0), ("DIRECTED", 14, 1), ("DIRECTED", 15, 1),
            ("DIRECTED", 14, 3), ("DIRECTED", 17, 2),
        ]
        return pairs.enumerated().map { index, pair in
            var properties: [String: PropertyValue] = ["createdAt": .date(date(2024, 3, 14, 9, 30))]
            if pair.0 == "ACTED_IN" {
                properties["roles"] = .list([.string("Role \(index + 1)")])
            }
            return GraphRelationship(id: 100 + index, type: pair.0, startNodeID: pair.1, endNodeID: pair.2, properties: properties)
        }
    }()
}
