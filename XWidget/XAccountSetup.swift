import SwiftUI
import AuthenticationServices

/// The "X Account" settings section: a step-by-step guide until signed in, then a compact status row.
struct XAccountSection: View {
    let store: FeedStore

    @AppStorage(SettingsKey.clientID, store: AppGroup.defaults) private var clientID = ""
    @State private var signedIn = TokenStore.load() != nil
    @State private var showGuide = false
    @State private var authError: String?
    @State private var signIn = SignInController()

    static let consoleURL = URL(string: "https://console.x.com")!
    static let websiteURL = "https://x.com"

    var body: some View {
        Section("X Account") {
            if signedIn {
                HStack {
                    Label("Signed in to X", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Spacer()
                    Button("Sign Out") { TokenStore.clear(); signedIn = false; refresh() }
                }
                DisclosureGroup("Setup guide", isExpanded: $showGuide) { steps }
            } else {
                steps
            }
        }
    }

    @ViewBuilder
    private var steps: some View {
        SetupStep(number: 1, title: "Create a client application") {
            Text("Sign in to the X Developer Console and create a new client application. Name it anything (e.g. **X Widget**) and keep **Default Project (Pay Per Use)** checked — any environment is fine. The project needs credits for reads.")
            Link(destination: Self.consoleURL) {
                Label("Open console.x.com", systemImage: "arrow.up.forward.app")
            }
        }

        SetupStep(number: 2, title: "Set up user authentication") {
            Text("Open your app's **Keys & Tokens** tab. Under **OAuth 2.0 Keys**, click **Set up** next to *User authentication settings* and enter:")
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow { Text("App permissions").foregroundStyle(.secondary); Text("Read") }
                GridRow { Text("Type of App").foregroundStyle(.secondary); Text("Native App") }
                GridRow { Text("Callback URI / Redirect URL").foregroundStyle(.secondary); CopyField(value: XAuth.redirectURI) }
                GridRow { Text("Website URL").foregroundStyle(.secondary); CopyField(value: Self.websiteURL) }
            }
            Text("Any website URL works. Leave *Request email from users* off and the other fields blank, then click **Save Changes**.")
        }

        SetupStep(number: 3, title: "Paste your OAuth 2.0 Client ID", isDone: !clientID.isEmpty) {
            Text("After saving, X shows your **Client ID** — it's also listed under **OAuth 2.0 Keys** on Keys & Tokens. Ignore the Bearer Token and OAuth 1.0 keys; they can't read your timeline. A Native App has no Client Secret.")
            HStack {
                TextField("Client ID", text: $clientID, prompt: Text("Paste Client ID"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                Button("Paste") {
                    if let text = NSPasteboard.general.string(forType: .string) {
                        clientID = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
        }

        SetupStep(number: 4, title: "Sign in", isDone: signedIn) {
            Button("Sign in with X") { Task { await startSignIn() } }
                .buttonStyle(.borderedProminent)
                .disabled(clientID.isEmpty || signedIn)
            if let authError {
                Text(authError).foregroundStyle(.red).textSelection(.enabled)
            }
        }
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

private struct SetupStep<Content: View>: View {
    let number: Int
    let title: String
    var isDone = false
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            ZStack {
                Circle().fill(isDone ? Color.green : Color.accentColor.opacity(0.15))
                if isDone {
                    Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.caption.bold()).foregroundStyle(Color.accentColor)
                }
            }
            .frame(width: 22, height: 22)
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }

            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                content
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}

/// A selectable value with a one-click copy button.
private struct CopyField: View {
    let value: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 6) {
            Text(value)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .lineLimit(1)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .help("Copy")
        }
    }
}
