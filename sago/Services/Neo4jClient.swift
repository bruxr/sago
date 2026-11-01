//
//  Neo4jClient.swift
//  sago
//

import Foundation

/// Credentials entered in the login form.
struct Credentials: Codable, Hashable {
    var host: String
    var user: String
    var password: String
}

/// Reasons a connection attempt can fail.
enum AuthError: Error, Equatable {
    case invalidHost
    case invalidCredentials
    case unreachable(String)
    case server(String)

    var message: String {
        switch self {
        case .invalidHost: "Enter a valid host."
        case .invalidCredentials: "Incorrect user or password."
        case .unreachable(let message): message
        case .server(let message): message
        }
    }
}

/// Talks to a neo4j server over its HTTP API.
enum Neo4jClient {
    static let database = "neo4j"

    /// Builds the server base URL from the host field.
    /// Uses `http://` unless `https://` is given, and the default neo4j HTTP ports when none is given.
    static func normalizedURL(host: String) -> URL? {
        var rest = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rest.isEmpty else { return nil }

        var scheme = "http"
        if let range = rest.range(of: "://") {
            if rest[..<range.lowerBound].lowercased() == "https" {
                scheme = "https"
            }
            rest = String(rest[range.upperBound...])
        }

        guard var components = URLComponents(string: "\(scheme)://\(rest)"),
              let hostName = components.host, !hostName.isEmpty
        else { return nil }

        components.scheme = scheme
        components.port = components.port ?? (scheme == "https" ? 7473 : 7474)
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }

    /// Verifies the credentials by running a trivial query. Throws `AuthError` on failure.
    static func verify(_ credentials: Credentials) async throws -> URL {
        guard let baseURL = normalizedURL(host: credentials.host) else {
            throw AuthError.invalidHost
        }
        _ = try await run([Statement("RETURN 1")], credentials: credentials)
        return baseURL
    }

    // MARK: - Queries

    /// Total number of nodes and relationships in the database. Both counts come from neo4j's count store.
    static func fetchCounts(credentials: Credentials) async throws -> (nodes: Int, relationships: Int) {
        let results = try await run([
            Statement("MATCH (n) RETURN count(n)"),
            Statement("MATCH ()-[r]->() RETURN count(r)"),
        ], credentials: credentials)
        let nodes = results.first?.rows.first?.first?.intValue ?? 0
        let relationships = results.dropFirst().first?.rows.first?.first?.intValue ?? 0
        return (nodes, relationships)
    }

    /// Fetches only what the canvas draws: id, labels and the caption fields (`name` / `title`).
    static func fetchNodes(limit: Int, credentials: Credentials) async throws -> [GraphNode] {
        let results = try await run([
            Statement(
                "MATCH (n) WITH n LIMIT $limit RETURN id(n), labels(n), n.name, n.title",
                parameters: ["limit": .int(limit)]
            ),
        ], credentials: credentials)
        return (results.first?.rows ?? []).compactMap(GraphNode.init(row:))
    }

    /// Fetches the id, type and endpoints of relationships whose both ends are in `nodeIDs`.
    static func fetchRelationships(between nodeIDs: [Int], limit: Int, credentials: Credentials) async throws -> [GraphRelationship] {
        guard !nodeIDs.isEmpty else { return [] }
        let results = try await run([
            Statement(
                "MATCH (a)-[r]->(b) WHERE id(a) IN $ids AND id(b) IN $ids RETURN id(r), type(r), id(a), id(b) LIMIT $limit",
                parameters: ["ids": .array(nodeIDs.map { .int($0) }), "limit": .int(limit)]
            ),
        ], credentials: credentials)
        return (results.first?.rows ?? []).compactMap(GraphRelationship.init(row:))
    }

    /// Fetches every property of the selected node or relationship.
    static func fetchProperties(of selection: GraphSelection, credentials: Credentials) async throws -> [String: PropertyValue] {
        let statement = switch selection {
        case .node(let id):
            Statement("MATCH (n) WHERE id(n) = $id RETURN properties(n)", parameters: ["id": .int(id)])
        case .relationship(let id):
            Statement("MATCH ()-[r]->() WHERE id(r) = $id RETURN properties(r)", parameters: ["id": .int(id)])
        }
        let results = try await run([statement], credentials: credentials)
        guard case .object(let object) = results.first?.rows.first?.first else { return [:] }
        return object.compactMapValues(\.propertyValue)
    }

    /// What a user query returned: the graph elements in its results plus enough to judge its outcome.
    struct UserQueryResult {
        var nodes: [GraphNode] = []
        var relationships: [GraphRelationship] = []
        var rowCount = 0
        var containsUpdates = false
    }

    /// Runs a cypher query typed by the user, collecting every node and relationship it returns.
    static func runQuery(_ cypher: String, credentials: Credentials) async throws -> UserQueryResult {
        var statement = Statement(cypher)
        statement.resultDataContents = ["row", "graph"]
        statement.includeStats = true
        return userQueryResult(from: try await run([statement], credentials: credentials))
    }

    /// Merges the per-row graphs, dropping duplicates and relationships whose ends are missing.
    static func userQueryResult(from results: [QueryResult]) -> UserQueryResult {
        var result = UserQueryResult()
        var nodeIDs = Set<Int>()
        var relationshipIDs = Set<Int>()
        var relationships: [GraphRelationship] = []
        for queryResult in results {
            result.rowCount += queryResult.rows.count
            result.containsUpdates = result.containsUpdates || queryResult.containsUpdates
            for graph in queryResult.graphs {
                for node in graph.nodes where nodeIDs.insert(node.id).inserted {
                    result.nodes.append(node)
                }
                for relationship in graph.relationships where relationshipIDs.insert(relationship.id).inserted {
                    relationships.append(relationship)
                }
            }
        }
        result.relationships = relationships.filter {
            nodeIDs.contains($0.startNodeID) && nodeIDs.contains($0.endNodeID)
        }
        return result
    }

    // MARK: - Transport

    /// A cypher statement with its parameters.
    struct Statement: Encodable {
        let statement: String
        var parameters: [String: JSONValue] = [:]
        /// Plain rows by default; the graph format ships every property of every element.
        var resultDataContents = ["row"]
        var includeStats = false

        init(_ statement: String, parameters: [String: JSONValue] = [:]) {
            self.statement = statement
            self.parameters = parameters
        }
    }

    /// The rows returned by one statement, plus their graphs and stats when requested.
    struct QueryResult: Decodable {
        let columns: [String]
        let rows: [[JSONValue]]
        /// One per row when the `graph` format was requested.
        let graphs: [Graph]
        let containsUpdates: Bool

        private enum CodingKeys: String, CodingKey { case columns, data, stats }
        private struct Row: Decodable {
            let row: [JSONValue]
            let graph: Graph?
        }
        private struct Stats: Decodable {
            let containsUpdates: Bool
            private enum CodingKeys: String, CodingKey { case containsUpdates = "contains_updates" }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            columns = try container.decode([String].self, forKey: .columns)
            let data = try container.decode([Row].self, forKey: .data)
            rows = data.map(\.row)
            graphs = data.compactMap(\.graph)
            containsUpdates = try container.decodeIfPresent(Stats.self, forKey: .stats)?.containsUpdates ?? false
        }
    }

    /// The nodes and relationships referenced by one row, in the HTTP API's graph format (ids are strings).
    struct Graph: Decodable {
        let nodes: [GraphNode]
        let relationships: [GraphRelationship]

        private enum CodingKeys: String, CodingKey { case nodes, relationships }
        private struct Node: Decodable {
            let id: String
            let labels: [String]
            let properties: [String: JSONValue]
        }
        private struct Relationship: Decodable {
            let id: String
            let type: String
            let startNode: String
            let endNode: String
            let properties: [String: JSONValue]
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            nodes = try container.decode([Node].self, forKey: .nodes).compactMap { node in
                guard let id = Int(node.id) else { return nil }
                return GraphNode(id: id, labels: node.labels, properties: node.properties.compactMapValues(\.propertyValue))
            }
            relationships = try container.decode([Relationship].self, forKey: .relationships).compactMap { relationship in
                guard let id = Int(relationship.id),
                      let start = Int(relationship.startNode),
                      let end = Int(relationship.endNode)
                else { return nil }
                return GraphRelationship(
                    id: id, type: relationship.type, startNodeID: start, endNodeID: end,
                    properties: relationship.properties.compactMapValues(\.propertyValue)
                )
            }
        }
    }

    /// Body returned by the transaction endpoint.
    struct Response: Decodable {
        struct QueryError: Decodable {
            let code: String
            let message: String
        }
        let results: [QueryResult]
        let errors: [QueryError]
    }

    /// Decodes a transaction response, turning cypher errors into `AuthError.server`.
    static func decodeResponse(_ data: Data) throws -> [QueryResult] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        if let error = response.errors.first {
            throw AuthError.server(error.message)
        }
        return response.results
    }

    /// Runs the statements in a single auto-committed transaction. Throws `AuthError` on failure.
    static func run(_ statements: [Statement], credentials: Credentials) async throws -> [QueryResult] {
        guard let baseURL = normalizedURL(host: credentials.host) else {
            throw AuthError.invalidHost
        }

        var request = URLRequest(url: baseURL.appending(path: "db/\(database)/tx/commit"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let token = Data("\(credentials.user):\(credentials.password)".utf8).base64EncodedString()
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(["statements": statements])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            // The calling task was cancelled, e.g. the user selected another element.
            throw CancellationError()
        } catch {
            throw AuthError.unreachable(error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300:
            do {
                return try decodeResponse(data)
            } catch let error as AuthError {
                throw error
            } catch {
                throw AuthError.server("Unexpected response from server.")
            }
        case 401, 403:
            throw AuthError.invalidCredentials
        default:
            throw AuthError.server("Server responded with status \(status).")
        }
    }
}

/// A JSON value as sent to / returned by the neo4j HTTP API.
enum JSONValue: Codable, Hashable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Bool before the numeric cases so `true`/`false` are never read as numbers.
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    var intValue: Int? {
        if case .int(let value) = self { value } else { nil }
    }

    var stringValue: String? {
        if case .string(let value) = self { value } else { nil }
    }

    /// The equivalent property value. Temporal values arrive as ISO strings and are kept as text;
    /// maps (e.g. points) are shown as their JSON-like description.
    var propertyValue: PropertyValue? {
        switch self {
        case .null: nil
        case .bool(let value): .bool(value)
        case .int(let value): .int(value)
        case .double(let value): .double(value)
        case .string(let value): .string(value)
        case .array(let values): .list(values.compactMap(\.propertyValue))
        case .object(let object):
            .string("{" + object.sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value.propertyValue?.displayString ?? "null")" }
                .joined(separator: ", ") + "}")
        }
    }
}

private extension GraphNode {
    /// Parses a `id(n), labels(n), n.name, n.title` row.
    init?(row: [JSONValue]) {
        guard row.count == 4, let id = row[0].intValue, case .array(let labels) = row[1] else { return nil }
        var properties: [String: PropertyValue] = [:]
        if let name = row[2].stringValue { properties["name"] = .string(name) }
        if let title = row[3].stringValue { properties["title"] = .string(title) }
        self.init(id: id, labels: labels.compactMap(\.stringValue), properties: properties)
    }
}

private extension GraphRelationship {
    /// Parses a `id(r), type(r), id(a), id(b)` row.
    init?(row: [JSONValue]) {
        guard row.count == 4,
              let id = row[0].intValue,
              let type = row[1].stringValue,
              let start = row[2].intValue,
              let end = row[3].intValue
        else { return nil }
        self.init(id: id, type: type, startNodeID: start, endNodeID: end)
    }
}
