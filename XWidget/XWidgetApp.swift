import SwiftUI

@main
struct XWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("X Widget", systemImage: "text.bubble") {
            MenuContent(store: appDelegate.store, overlay: appDelegate.overlay)
        }

        Settings {
            SettingsView(store: appDelegate.store, overlay: appDelegate.overlay)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = FeedStore()
    lazy var overlay = DesktopOverlayController(store: store)

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppGroup.defaults.register(defaults: [
            SettingsKey.pollInterval: 120.0,
            SettingsKey.overlayEnabled: true,
            SettingsKey.overlayEdge: OverlayEdge.right.rawValue,
            SettingsKey.overlayWidth: 380.0,
            SettingsKey.overlayStyle: OverlayStyle.glass.rawValue,
            SettingsKey.overlayFeed: FeedKind.following.rawValue,
        ])
        store.start()
        overlay.applySettings()
    }

    /// Widget taps arrive as xwidget://open?url=<post url>.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.host() == "open" {
            let target = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "url" })?.value
            if let target, let postURL = URL(string: target) { NSWorkspace.shared.open(postURL) }
        }
    }
}

private struct MenuContent: View {
    let store: FeedStore
    let overlay: DesktopOverlayController

    var body: some View {
        Button(overlay.isVisible ? "Hide Desktop Feed" : "Show Desktop Feed") { overlay.toggle() }
        DisplayPicker(overlay: overlay)
        Button("Refresh Now") { Task { await store.refreshAll() } }
            .keyboardShortcut("r")
        Divider()
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Divider()
        Button("Quit X Widget") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
