//
//  CypherHighlighterTests.swift
//  sagoTests
//

import Foundation
import SwiftUI
import Testing
@testable import sago

struct CypherHighlighterTests {
    /// The highlighted substrings of `text` with their token kinds.
    private func tokens(_ text: String) -> [(CypherHighlighter.Token, String)] {
        CypherHighlighter.tokens(in: text).map { ($0.token, (text as NSString).substring(with: $0.range)) }
    }

    @Test func highlightsKeywordsLabelsParametersAndFunctions() {
        let result = tokens("match (p:Person) WHERE p.born > $year RETURN count(p) LIMIT 10")
        #expect(result.map(\.0) == [.keyword, .label, .keyword, .parameter, .keyword, .function, .keyword, .number])
        #expect(result.map(\.1) == ["match", ":Person", "WHERE", "$year", "RETURN", "count", "LIMIT", "10"])
    }

    @Test func ignoresKeywordsInsideStringsAndComments() {
        let result = tokens("RETURN 'MATCH (n)' // WHERE x")
        #expect(result.map(\.0) == [.keyword, .string, .comment])
        #expect(result.map(\.1) == ["RETURN", "'MATCH (n)'", "// WHERE x"])
    }

    @Test func highlightsUnterminatedString() {
        #expect(tokens(#"RETURN "abc"#).map(\.0) == [.keyword, .string])
    }

    @Test func classifiesQueryEffect() {
        #expect(CypherHighlighter.effect(of: "MATCH (n) RETURN n") == .read)
        #expect(CypherHighlighter.effect(of: "CREATE (n:Person)") == .write)
        #expect(CypherHighlighter.effect(of: "match (n) set n.x = 1") == .write)
        #expect(CypherHighlighter.effect(of: "MERGE (n:Person {name: 'A'})") == .write)
        #expect(CypherHighlighter.effect(of: "MATCH (n) DETACH DELETE n") == .delete)
        #expect(CypherHighlighter.effect(of: "MATCH (n) REMOVE n.x") == .delete)
        #expect(CypherHighlighter.effect(of: "CREATE (a) WITH a MATCH (b) DELETE b") == .delete)
    }

    @Test func classifiesProcedureCalls() {
        #expect(CypherHighlighter.effect(of: "CALL db.labels()") == .procedure)
        #expect(CypherHighlighter.effect(of: "call apoc.periodic.iterate('a', 'b', {})") == .procedure)
        #expect(CypherHighlighter.effect(of: "CALL db.labels() YIELD label CREATE (:Tag {name: label})") == .procedure)
        #expect(CypherHighlighter.effect(of: "CALL apoc.x() YIELD n DETACH DELETE n") == .delete)
        // Subqueries aren't procedure calls.
        #expect(CypherHighlighter.effect(of: "CALL { MATCH (n) RETURN n } RETURN n") == .read)
        #expect(CypherHighlighter.effect(of: "MATCH (a) CALL (a) { CREATE (b) } RETURN a") == .write)
    }

    @Test func ignoresEffectKeywordsInsideStringsAndComments() {
        #expect(CypherHighlighter.effect(of: "RETURN 'CREATE' // DELETE") == .read)
    }

    @Test func recolorsAttributedStringWithoutChangingText() {
        var text = AttributedString("MATCH (n) RETURN n")
        CypherHighlighter.highlight(&text)
        #expect(String(text.characters) == "MATCH (n) RETURN n")
        let colored = text.runs.filter { $0.foregroundColor != nil }.map { String(text[$0.range].characters) }
        #expect(colored == ["MATCH", "RETURN"])
    }
}
