//
//  LoginView.swift
//  sago
//

import SwiftUI

/// Form for entering the server address and credentials.
struct LoginView: View {
    let session: ConnectionSession

    @State private var host = ""
    @State private var user = ""
    @State private var password = ""
    @State private var shakes: CGFloat = 0
    @State private var credentialsInvalid = false

    private var isConnecting: Bool { session.state == .connecting }

    private var canConnect: Bool {
        !isConnecting
            && !host.trimmingCharacters(in: .whitespaces).isEmpty
            && !user.isEmpty
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 36))
                    .foregroundStyle(.tint)
                Text("Connect to Neo4j")
                    .font(.title2.bold())
            }

            VStack(alignment: .leading, spacing: 12) {
                field("Host") {
                    TextField("Host", text: $host, prompt: Text("localhost:7474"))
                        .textContentType(.URL)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                }
                field("User", invalid: credentialsInvalid) {
                    TextField("User", text: $user, prompt: Text("neo4j"))
                        .textContentType(.username)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                }
                field("Password", invalid: credentialsInvalid) {
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }
            }
            .autocorrectionDisabled()
            .disabled(isConnecting)
            .modifier(ShakeEffect(shakes: shakes))

            if let error = session.lastError {
                Text(error.message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: connect) {
                ZStack {
                    Text("Connect").opacity(isConnecting ? 0 : 1)
                    if isConnecting {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!canConnect)
        }
        .padding(28)
        .frame(width: 360)
        .glassEffect(in: .rect(cornerRadius: 24))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if let saved = session.savedCredentials {
                host = saved.host
                user = saved.user
                password = saved.password
            }
        }
        .onChange(of: session.lastError) {
            guard session.lastError == .invalidCredentials else { return }
            credentialsInvalid = true
            withAnimation(.linear(duration: 0.4)) { shakes += 1 }
        }
        .onChange(of: user) { credentialsInvalid = false }
        .onChange(of: password) { credentialsInvalid = false }
    }

    private func field<Content: View>(
        _ title: LocalizedStringKey,
        invalid: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.red, lineWidth: 1.5)
                        .opacity(invalid ? 1 : 0)
                        .allowsHitTesting(false)
                }
                .accessibilityValue(invalid ? Text("Invalid") : Text(""))
        }
    }

    private func connect() {
        guard canConnect else { return }
        let credentials = Credentials(host: host, user: user, password: password)
        Task { await session.connect(credentials) }
    }
}

#Preview {
    LoginView(session: ConnectionSession())
        .frame(width: 600, height: 500)
}
