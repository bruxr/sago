//
//  Neo4jClientTests.swift
//  sagoTests
//

import Foundation
import Testing
@testable import sago

struct Neo4jClientTests {
    @Test(arguments: [
        ("localhost", "http://localhost:7474"),
        ("localhost:7687", "http://localhost:7687"),
        ("  db.example.com  ", "http://db.example.com:7474"),
        ("https://db.example.com", "https://db.example.com:7473"),
        ("HTTPS://db.example.com:9000/browser", "https://db.example.com:9000"),
        ("http://localhost:7474/", "http://localhost:7474"),
        ("neo4j://localhost", "http://localhost:7474"),
    ])
    func normalizesHost(input: String, expected: String) {
        #expect(Neo4jClient.normalizedURL(host: input)?.absoluteString == expected)
    }

    @Test(arguments: ["", "   ", "https://"])
    func rejectsEmptyHost(input: String) {
        #expect(Neo4jClient.normalizedURL(host: input) == nil)
    }

    @Test func decodesRows() throws {
        let json = #"""
        {"results":[{"columns":["id(n)","labels(n)","n.name","n.title"],
          "data":[{"row":[7,["Person","Actor"],"Keanu",null],"meta":[null,null,null,null]}]}],
         "errors":[]}
        """#
        let results = try Neo4jClient.decodeResponse(Data(json.utf8))
        #expect(results.first?.rows == [[.int(7), .array([.string("Person"), .string("Actor")]), .string("Keanu"), .null]])
    }

    @Test func throwsCypherErrors() {
        let json = #"{"results":[],"errors":[{"code":"Neo.ClientError.Statement.SyntaxError","message":"Invalid input"}]}"#
        #expect(throws: AuthError.server("Invalid input")) {
            try Neo4jClient.decodeResponse(Data(json.utf8))
        }
    }

    @Test func mapsPropertyValues() throws {
        let json = #"[true, 42, 1.5, "x", [1, "a"], null]"#
        let values = try JSONDecoder().decode([JSONValue].self, from: Data(json.utf8)).map(\.propertyValue)
        #expect(values == [.bool(true), .int(42), .double(1.5), .string("x"), .list([.int(1), .string("a")]), nil])
    }

    @Test func decodesGraphResults() throws {
        let json = #"""
        {"results":[{"columns":["a","r","b"],
          "data":[
            {"row":[{},{},{}],"graph":{
              "nodes":[{"id":"1","labels":["Person"],"properties":{"name":"Keanu","born":1964}},
                       {"id":"2","labels":["Movie"],"properties":{"title":"The Matrix"}}],
              "relationships":[{"id":"10","type":"ACTED_IN","startNode":"1","endNode":"2","properties":{"roles":["Neo"]}},
                               {"id":"11","type":"DIRECTED","startNode":"3","endNode":"2","properties":{}}]}},
            {"row":[{},{},{}],"graph":{
              "nodes":[{"id":"1","labels":["Person"],"properties":{"name":"Keanu","born":1964}}],
              "relationships":[{"id":"10","type":"ACTED_IN","startNode":"1","endNode":"2","properties":{"roles":["Neo"]}}]}}],
          "stats":{"contains_updates":false,"nodes_created":0}}],
         "errors":[]}
        """#
        let result = Neo4jClient.userQueryResult(from: try Neo4jClient.decodeResponse(Data(json.utf8)))
        #expect(result.rowCount == 2)
        #expect(!result.containsUpdates)
        #expect(result.nodes.map(\.id) == [1, 2])
        #expect(result.nodes.first?.properties == ["name": .string("Keanu"), "born": .int(1964)])
        // Duplicate dropped; relationship to the missing node 3 dropped.
        #expect(result.relationships.map(\.id) == [10])
        #expect(result.relationships.first?.properties == ["roles": .list([.string("Neo")])])
    }

    @Test func decodesUpdateStats() throws {
        let json = #"{"results":[{"columns":[],"data":[],"stats":{"contains_updates":true}}],"errors":[]}"#
        let result = Neo4jClient.userQueryResult(from: try Neo4jClient.decodeResponse(Data(json.utf8)))
        #expect(result.rowCount == 0)
        #expect(result.containsUpdates)
        #expect(GraphStore.status(for: result) == .succeeded)
    }

    @Test func classifiesQueryStatus() {
        #expect(GraphStore.status(for: .init(rowCount: 3)) == .succeeded)
        #expect(GraphStore.status(for: .init()) == .empty)
    }
}
