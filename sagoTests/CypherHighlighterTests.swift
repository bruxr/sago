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

    @Test func recolorsAttributedStringWithoutChangingText() {
        var text = AttributedString("MATCH (n) RETURN n")
        CypherHighlighter.highlight(&text)
        #expect(String(text.characters) == "MATCH (n) RETURN n")
        let colored = text.runs.filter { $0.foregroundColor != nil }.map { String(text[$0.range].characters) }
        #expect(colored == ["MATCH", "RETURN"])
    }
}
