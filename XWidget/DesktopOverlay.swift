import SwiftUI

enum OverlayEdge: String, CaseIterable, Identifiable {
    case left, right
    var id: String { rawValue }
}

enum OverlayStyle: String, CaseIterable, Identifiable {
    case glass, clear
    var id: String { rawValue }
    var title: String { self == .glass ? "Glass cards" : "No background" }
}

/// A borderless, full-height panel that lives on the desktop layer — below app windows, above wallpaper/icons.
/// This is what WidgetKit can't do: no widget box, any height, and live updates.
@MainActor
@Observable
final class DesktopOverlayController {
    @ObservationIgnored private let store: FeedStore
    @ObservationIgnored private var panel: NSPanel?
    private(set) var isVisible = false

    init(store: FeedStore) {
        self.store = store
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
    }

    func applySettings() {
        AppGroup.defaults.bool(forKey: SettingsKey.overlayEnabled) ? show() : hide()
        layout()
    }

    func toggle() {
        isVisible ? hide() : show()
        AppGroup.defaults.set(isVisible, forKey: SettingsKey.overlayEnabled)
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        layout()
        panel.orderFrontRegardless()
        isVisible = true
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: DesktopFeedView(store: store))
        return panel
    }

    private func layout() {
        guard let panel, let screen = OverlayDisplay.selectedScreen else { return }
        let visible = screen.visibleFrame
        let width = CGFloat(AppGroup.defaults.double(forKey: SettingsKey.overlayWidth))
        let edge = OverlayEdge(rawValue: AppGroup.defaults.string(forKey: SettingsKey.overlayEdge) ?? "") ?? .right
        let inset: CGFloat = 12
        let x = edge == .right ? visible.maxX - width - inset : visible.minX + inset
        panel.setFrame(NSRect(x: x, y: visible.minY + inset, width: width, height: visible.height - inset * 2), display: true)
    }
}

/// Identifies a monitor by name, which (unlike CGDirectDisplayID) survives reboots and reconnects.
enum OverlayDisplay {
    /// Empty means "follow the main display".
    static let main = ""

    static var names: [String] { NSScreen.screens.map(\.localizedName) }

    /// Falls back to the main (menu bar) display if the chosen monitor is disconnected.
    /// `NSScreen.main` isn't used because it follows keyboard focus.
    static var selectedScreen: NSScreen? {
        let name = AppGroup.defaults.string(forKey: SettingsKey.overlayDisplay) ?? main
        return NSScreen.screens.first { $0.localizedName == name } ?? NSScreen.screens.first
    }
}

struct DisplayPicker: View {
    let overlay: DesktopOverlayController
    @AppStorage(SettingsKey.overlayDisplay, store: AppGroup.defaults) private var display = OverlayDisplay.main

    var body: some View {
        Picker("Display", selection: $display) {
            Text("Main Display").tag(OverlayDisplay.main)
            ForEach(OverlayDisplay.names, id: \.self) { Text($0).tag($0) }
        }
        .onChange(of: display) { overlay.applySettings() }
    }
}

struct DesktopFeedView: View {
    let store: FeedStore
    @AppStorage(SettingsKey.overlayFeed, store: AppGroup.defaults) private var feed = FeedKind.following
    @AppStorage(SettingsKey.overlayStyle, store: AppGroup.defaults) private var style = OverlayStyle.glass
    @Environment(\.openURL) private var openURL

    private static let shadowRoom: CGFloat = 8

    var body: some View {
        let snapshot = store.snapshot(feed)
        VStack(alignment: .leading, spacing: 10) {
            header(snapshot)
                .modifier(LegibilityShadow(style: style))
            if let message = snapshot.status.message {
                Text(message)
                    .font(.caption)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .modifier(CardBackground(style: style))
                    .modifier(LegibilityShadow(style: style))
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(snapshot.posts) { post in
                        Button { openURL(post.url) } label: {
                            PostRow(post: post, lineLimit: 5, avatarSize: 32)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                                .modifier(CardBackground(style: style))
                                .modifier(LegibilityShadow(style: style))
                        }
                        .buttonStyle(.plain)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                // Room for card edges and shadows, which the scroll view would otherwise clip.
                .padding(.horizontal, Self.shadowRoom)
                .padding(.vertical, Self.shadowRoom)
            }
            .padding(.horizontal, -Self.shadowRoom)
            .scrollIndicators(.never)
            // Lets the last post scroll clear of the bottom fade.
            .contentMargins(.bottom, 60, for: .scrollContent)
            .mask(LinearGradient(stops: [.init(color: .black, location: 0.9), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
        }
        .padding(Self.shadowRoom)
        // macOS passes mouse and scroll events through fully transparent pixels to the desktop,
        // so give the whole panel an invisible (but non-zero alpha) backing to keep scrolling anywhere in it.
        .background(Color.black.opacity(0.01))
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    private func header(_ snapshot: FeedSnapshot) -> some View {
        HStack(spacing: 6) {
            ForEach(FeedKind.allCases) { kind in
                Button(kind.title) { withAnimation(.snappy) { feed = kind } }
                    .buttonStyle(.plain)
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .opacity(feed == kind ? 1 : 0.55)
                    .glassEffect(feed == kind ? .regular.interactive() : .identity, in: .capsule)
            }
            Spacer()
            if store.isRefreshing {
                ProgressView().controlSize(.small)
            } else if snapshot.updatedAt > .distantPast {
                Text(snapshot.updatedAt, style: .relative).font(.caption2).opacity(0.7)
            }
            Text("𝕏").font(.title2.weight(.bold))
        }
    }
}

private struct CardBackground: ViewModifier {
    let style: OverlayStyle

    func body(content: Content) -> some View {
        switch style {
        case .glass: content.glassEffect(.regular, in: .rect(cornerRadius: 16))
        case .clear: content
        }
    }
}

/// Applied per element: a shadow on the whole panel gets clipped by the scroll view and window bounds.
private struct LegibilityShadow: ViewModifier {
    let style: OverlayStyle

    func body(content: Content) -> some View {
        switch style {
        case .glass: content
        case .clear: content.shadow(color: .black.opacity(0.6), radius: 3, y: 1)
        }
    }
}
