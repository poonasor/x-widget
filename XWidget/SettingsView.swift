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
    @AppStorage(SettingsKey.showMedia, store: AppGroup.defaults) private var showMedia = true

    private enum SettingsTab: Hashable { case general, account }
    // New users land on X Account so setup is the first thing they see.
    @State private var tab: SettingsTab = TokenStore.load() == nil ? .account : .general

    var body: some View {
        TabView(selection: $tab) {
            Tab("Settings", systemImage: "gearshape", value: .general) { generalForm }
            Tab("X Account", systemImage: "person.crop.circle", value: .account) {
                Form { XAccountSection(store: store) }
                    .formStyle(.grouped)
                    .frame(width: 500)
                    .frame(minHeight: 420, idealHeight: 720)
            }
        }
        .onAppear { NSApp.activate() }
        .onChange(of: clientID) { refresh() }
    }

    private var generalForm: some View {
        Form {
            Section("General") {
                LaunchAtLoginToggle()
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
                Toggle("Show images", isOn: $showMedia)
                Slider(value: $width, in: 300...560, step: 10) { Text("Width") }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: overlayEnabled) { overlay.applySettings() }
        .onChange(of: edge) { overlay.applySettings() }
        .onChange(of: width) { overlay.applySettings() }
        .onChange(of: pollInterval) { store.start() }
    }

    private func refresh() { Task { await store.refreshAll() } }
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
            let session = ASWebAuthenticationSession(url: components.url!, callback: .customScheme("xwidget")) { @Sendable url, error in
                // Called on a background XPC queue; @Sendable stops it inheriting MainActor isolation (which traps).
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
        let anchor = { @MainActor in NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible } ?? ASPresentationAnchor() }
        return Thread.isMainThread ? MainActor.assumeIsolated(anchor) : DispatchQueue.main.sync(execute: anchor)
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
