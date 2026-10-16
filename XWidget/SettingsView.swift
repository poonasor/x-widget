import SwiftUI
import AuthenticationServices
import CryptoKit

struct SettingsView: View {
    let store: FeedStore
    let overlay: DesktopOverlayController

    @AppStorage(SettingsKey.clientID, store: AppGroup.defaults) private var clientID = ""
    @AppStorage(SettingsKey.pollInterval, store: AppGroup.defaults) private var pollInterval = 120.0
    @AppStorage(SettingsKey.overlayEnabled, store: AppGroup.defaults) private var overlayEnabled = true
    @AppStorage(SettingsKey.overlayEdge, store: AppGroup.defaults) private var edge = OverlayEdge.right
    @AppStorage(SettingsKey.overlayWidth, store: AppGroup.defaults) private var width = 380.0
    @AppStorage(SettingsKey.overlayStyle, store: AppGroup.defaults) private var style = OverlayStyle.glass

    @State private var signedIn = TokenStore.load() != nil
    @State private var authError: String?
    @State private var signIn = SignInController()

    var body: some View {
        Form {
            Section("X Account") {
                TextField("OAuth 2.0 Client ID", text: $clientID)
                    .textFieldStyle(.roundedBorder)
                Text("Create a Native App in the X Developer Portal with callback **\(XAuth.redirectURI)** and paste its Client ID.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    if signedIn {
                        Label("Signed in", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Spacer()
                        Button("Sign Out") { TokenStore.clear(); signedIn = false; refresh() }
                    } else {
                        Button("Sign in with X") { Task { await startSignIn() } }
                            .disabled(clientID.isEmpty)
                    }
                }
                if let authError { Text(authError).font(.caption).foregroundStyle(.red) }
            }

            Section("Live Updates") {
                Picker("Poll every", selection: $pollInterval) {
                    Text("30 seconds").tag(30.0)
                    Text("1 minute").tag(60.0)
                    Text("2 minutes").tag(120.0)
                    Text("5 minutes").tag(300.0)
                    Text("15 minutes").tag(900.0)
                }
                Text("Each poll reads only new posts (since_id), but X API reads are billed — longer intervals cost less.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Desktop Feed") {
                Toggle("Show on desktop", isOn: $overlayEnabled)
                DisplayPicker(overlay: overlay)
                Picker("Screen edge", selection: $edge) {
                    ForEach(OverlayEdge.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
                Picker("Style", selection: $style) {
                    ForEach(OverlayStyle.allCases) { Text($0.title).tag($0) }
                }
                Slider(value: $width, in: 300...560, step: 10) { Text("Width") }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onAppear { NSApp.activate() }
        .onChange(of: overlayEnabled) { overlay.applySettings() }
        .onChange(of: edge) { overlay.applySettings() }
        .onChange(of: width) { overlay.applySettings() }
        .onChange(of: pollInterval) { store.start() }
        .onChange(of: clientID) { refresh() }
    }

    private func refresh() { Task { await store.refreshAll() } }

    private func startSignIn() async {
        authError = nil
        do {
            try await signIn.signIn(clientID: clientID)
            signedIn = true
            refresh()
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // User closed the sheet.
        } catch {
            authError = error.localizedDescription
        }
    }
}

/// Interactive OAuth 2.0 PKCE sign-in via ASWebAuthenticationSession.
@MainActor
final class SignInController: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func signIn(clientID: String) async throws {
        let verifier = Self.randomURLSafe(64)
        let state = Self.randomURLSafe(16)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded

        var components = URLComponents(url: XAuth.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: XAuth.redirectURI),
            .init(name: "scope", value: XAuth.scopes),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
        ]

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: components.url!, callback: .customScheme("xwidget")) { url, error in
                if let url { continuation.resume(returning: url) } else { continuation.resume(throwing: error ?? URLError(.unknown)) }
            }
            session.presentationContextProvider = self
            self.session = session
            session.start()
        }

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else {
            throw URLError(.badServerResponse)
        }

        let token = try await XAuth.requestToken([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": XAuth.redirectURI,
            "code_verifier": verifier,
            "client_id": clientID,
        ])
        TokenStore.save(token)
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible } ?? ASPresentationAnchor() }
    }

    private static func randomURLSafe(_ count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes).base64URLEncoded
    }
}

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
