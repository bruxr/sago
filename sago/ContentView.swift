//
//  ContentView.swift
//  sago
//
//  Created by Brux on 11/1/26.
//

import SwiftUI

struct ContentView: View {
    @State private var session = ConnectionSession()

    var body: some View {
        Group {
            switch session.state {
            case .restoring:
                ProgressView("Reconnecting…")
                    .frame(minWidth: 420, minHeight: 420)
            case .loggedOut, .connecting:
                LoginView(session: session)
                    .frame(minWidth: 420, minHeight: 420)
            case .connected(let connection):
                if let credentials = session.savedCredentials {
                    DatabaseView(connection: connection, graph: GraphStore(credentials: credentials), onLogout: session.logout)
                }
            }
        }
        .task { await session.restore() }
    }
}

#Preview {
    ContentView()
        .frame(width: 1200, height: 800)
}
