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
}
