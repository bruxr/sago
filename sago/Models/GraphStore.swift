//
//  GraphStore.swift
//  sago
//

import Foundation
import Observation

/// The graph shown on the canvas, the database totals and the lazily loaded element properties.
@Observable
final class GraphStore {
    /// Maximum number of nodes (and relationships) drawn on the canvas.
    static let limit = 1000

    var nodes: [GraphNode] = []
    var relationships: [GraphRelationship] = []
    /// Totals for the whole database; `nil` until loaded.
    var nodeCount: Int?
    var relationshipCount: Int?
    var isLoadingGraph = false
    var loadError: String?
    /// The user query in progress; only one runs at a time.
    private(set) var runningQuery: String?
    /// The last failed user query, shown in an alert.
    var queryError: QueryFailure?

    var isRunningQuery: Bool { runningQuery != nil }

    struct QueryFailure: Identifiable {
        let id = UUID()
        let cypher: String
        let message: String
    }

    private let credentials: Credentials?
    /// Properties fetched so far, keyed by element.
    private var details: [GraphSelection: [String: PropertyValue]] = [:]

    init(credentials: Credentials) {
        self.credentials = credentials
    }

    /// Fetches the database totals and the first nodes and relationships, concurrently.
    func load() async {
        guard let credentials else { return }
        loadError = nil
        async let counts: Void = loadCounts(credentials)
        await loadGraph(credentials)
        await counts
    }

    private func loadCounts(_ credentials: Credentials) async {
        do {
            (nodeCount, relationshipCount) = try await Neo4jClient.fetchCounts(credentials: credentials)
        } catch {
            report(error)
        }
    }

    private func loadGraph(_ credentials: Credentials) async {
        isLoadingGraph = true
        defer { isLoadingGraph = false }
        do {
            let nodes = try await Neo4jClient.fetchNodes(limit: Self.limit, credentials: credentials)
            let relationships = try await Neo4jClient.fetchRelationships(
                between: nodes.map(\.id), limit: Self.limit, credentials: credentials
            )
            details = [:]
            self.nodes = nodes
            self.relationships = relationships
        } catch {
            report(error)
        }
    }

    private func report(_ error: Error) {
        guard !(error is CancellationError) else { return }
        loadError = Self.message(for: error)
    }

    private static func message(for error: Error) -> String {
        (error as? AuthError)?.message ?? error.localizedDescription
    }

    /// Runs a user query, replacing the canvas with the graph it returns (if any).
    /// Returns its outcome, or `nil` if another query is running or it was cancelled.
    func run(_ cypher: String) async -> (status: QueryStatus, errorMessage: String?)? {
        guard let credentials, !isRunningQuery else { return nil }
        runningQuery = cypher
        defer { runningQuery = nil }
        do {
            let result = try await Neo4jClient.runQuery(cypher, credentials: credentials)
            if !result.nodes.isEmpty { show(result) }
            return (Self.status(for: result), nil)
        } catch is CancellationError {
            return nil
        } catch {
            let message = Self.message(for: error)
            queryError = QueryFailure(cypher: cypher, message: message)
            return (.failed, message)
        }
    }

    /// Succeeded when the query returned rows or changed the database; empty otherwise.
    static func status(for result: Neo4jClient.UserQueryResult) -> QueryStatus {
        result.rowCount > 0 || result.containsUpdates ? .succeeded : .empty
    }

    private func show(_ result: Neo4jClient.UserQueryResult) {
        let nodes = Array(result.nodes.prefix(Self.limit))
        let ids = Set(nodes.map(\.id))
        let relationships = Array(result.relationships
            .filter { ids.contains($0.startNodeID) && ids.contains($0.endNodeID) }
            .prefix(Self.limit))
        // Query results carry every property, so the inspector needs no extra fetch.
        details = [:]
        for node in nodes { details[.node(node.id)] = node.properties }
        for relationship in relationships { details[.relationship(relationship.id)] = relationship.properties }
        self.nodes = nodes
        self.relationships = relationships
    }

    /// The properties of the selected element, fetched from the server the first time.
    func properties(for selection: GraphSelection) async throws -> [String: PropertyValue] {
        if let cached = details[selection] { return cached }
        guard let credentials else { return [:] }
        let properties = try await Neo4jClient.fetchProperties(of: selection, credentials: credentials)
        details[selection] = properties
        return properties
    }

    /// Cached properties, if already loaded.
    func cachedProperties(for selection: GraphSelection) -> [String: PropertyValue]? {
        details[selection]
    }

    // MARK: - Previews

    private init(nodes: [GraphNode], relationships: [GraphRelationship]) {
        credentials = nil
        self.nodes = nodes
        self.relationships = relationships
        nodeCount = 12_480
        relationshipCount = 48_912
        for node in nodes { details[.node(node.id)] = node.properties }
        for relationship in relationships { details[.relationship(relationship.id)] = relationship.properties }
    }

    /// Sample data that never touches the network.
    static var preview: GraphStore {
        GraphStore(nodes: PlaceholderData.nodes, relationships: PlaceholderData.relationships)
    }
}
