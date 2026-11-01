//
//  CypherHighlighter.swift
//  sago
//

import SwiftUI

/// Minimal regex-based syntax highlighting for cypher.
enum CypherHighlighter {
    enum Token: Equatable {
        case comment, string, identifier, parameter, label, number, keyword, function
    }

    /// The only attribute the query editor keeps, so pasted styling is dropped.
    struct EditorScope: AttributeScope {
        let foregroundColor: AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute
    }

    static let keywords: Set<String> = [
        "MATCH", "OPTIONAL", "WHERE", "RETURN", "WITH", "CREATE", "MERGE", "SET", "DELETE", "DETACH",
        "REMOVE", "UNWIND", "ORDER", "BY", "ASC", "ASCENDING", "DESC", "DESCENDING", "LIMIT", "SKIP",
        "AND", "OR", "XOR", "NOT", "AS", "DISTINCT", "CALL", "YIELD", "UNION", "ALL", "CASE", "WHEN",
        "THEN", "ELSE", "END", "IS", "NULL", "IN", "ON", "INDEX", "CONSTRAINT", "IF", "EXISTS", "FOR",
        "REQUIRE", "UNIQUE", "DROP", "TRUE", "FALSE", "STARTS", "ENDS", "CONTAINS", "FOREACH", "LOAD",
        "CSV", "FROM", "HEADERS", "USE", "SHOW", "DATABASE", "DATABASES", "KEY", "NODE", "TRANSACTIONS",
    ]

    /// Alternatives are tried left to right at each position, so comments and strings win over what they contain.
    private static let pattern = try! NSRegularExpression(pattern: [
        #"(//[^\n]*|/\*[\s\S]*?(?:\*/|$))"#,          // 1 comment
        #"('(?:[^'\\]|\\.)*'?|"(?:[^"\\]|\\.)*"?)"#,  // 2 string
        #"(`[^`]*`?)"#,                               // 3 identifier
        #"(\$\w+)"#,                                  // 4 parameter
        #"(:[A-Za-z_]\w*)"#,                          // 5 label / type
        #"(\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b)"#,     // 6 number
        #"([A-Za-z_]\w*)"#,                           // 7 word
    ].joined(separator: "|"))

    private static let groups: [Token] = [.comment, .string, .identifier, .parameter, .label, .number]

    /// The highlighted tokens in `text`, as UTF-16 ranges.
    static func tokens(in text: String) -> [(token: Token, range: NSRange)] {
        let ns = text as NSString
        return pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            if let index = groups.indices.first(where: { match.range(at: $0 + 1).location != NSNotFound }) {
                return (groups[index], match.range)
            }
            let word = ns.substring(with: match.range)
            if keywords.contains(word.uppercased()) { return (.keyword, match.range) }
            // A word directly followed by `(` is a function call.
            let rest = ns.substring(from: NSMaxRange(match.range))
            if rest.drop(while: { $0 == " " }).first == "(" { return (.function, match.range) }
            return nil
        }
    }

    static func color(for token: Token) -> Color {
        switch token {
        case .comment: .secondary
        case .string: .red
        case .identifier: .brown
        case .parameter: .orange
        case .label: .teal
        case .number: .blue
        case .keyword: .pink
        case .function: .indigo
        }
    }

    /// Recolors `text` in place without changing its characters.
    static func highlight(_ text: inout AttributedString) {
        text.foregroundColor = nil
        let plain = String(text.characters)
        for (token, nsRange) in tokens(in: plain) {
            guard let range = Range(nsRange, in: text) else { continue }
            text[range].foregroundColor = color(for: token)
        }
    }

    static func highlighted(_ cypher: String) -> AttributedString {
        var text = AttributedString(cypher)
        highlight(&text)
        return text
    }
}
