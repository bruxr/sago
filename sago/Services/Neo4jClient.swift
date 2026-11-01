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

        var request = URLRequest(url: baseURL.appending(path: "db/\(database)/tx/commit"))
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let token = Data("\(credentials.user):\(credentials.password)".utf8).base64EncodedString()
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data(#"{"statements":[{"statement":"RETURN 1"}]}"#.utf8)

        let response: URLResponse
        do {
            (_, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AuthError.unreachable(error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300:
            return baseURL
        case 401, 403:
            throw AuthError.invalidCredentials
        default:
            throw AuthError.server("Server responded with status \(status).")
        }
    }
}
