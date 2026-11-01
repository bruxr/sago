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
}
