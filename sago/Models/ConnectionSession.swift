//
//  ConnectionSession.swift
//  sago
//

import Foundation
import Observation

/// Tracks whether the app is authenticated against a neo4j server.
@Observable
final class ConnectionSession {
    enum State: Equatable {
        case restoring
        case loggedOut
        case connecting
        case connected(ConnectionInfo)
    }

    var state: State = .restoring
    var lastError: AuthError?
    /// Prefills the login form, e.g. after a failed reconnect.
    var savedCredentials: Credentials?

    /// Reconnects with the credentials saved in the Keychain, if any.
    func restore() async {
        guard let credentials = CredentialStore.load() else {
            state = .loggedOut
            return
        }
        savedCredentials = credentials
        await connect(credentials, save: false)
    }

    /// Verifies the credentials and, if valid, saves them and shows the main interface.
    func connect(_ credentials: Credentials, save: Bool = true) async {
        lastError = nil
        if state != .restoring { state = .connecting }

        do {
            let url = try await Neo4jClient.verify(credentials)
            if save { try? CredentialStore.save(credentials) }
            savedCredentials = credentials
            state = .connected(ConnectionInfo(
                uri: url.absoluteString,
                database: Neo4jClient.database,
                user: credentials.user
            ))
        } catch {
            lastError = error as? AuthError ?? .server(error.localizedDescription)
            state = .loggedOut
        }
    }

    /// Forgets the saved credentials and returns to the login form, keeping host and user.
    func logout() {
        CredentialStore.delete()
        savedCredentials?.password = ""
        lastError = nil
        state = .loggedOut
    }
}
