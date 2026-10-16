import AppIntents
import SwiftUI
import WidgetKit

@main
struct FeedWidgetBundle: WidgetBundle {
    var body: some Widget { FeedWidget() }
}

struct FeedWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "XFeed", intent: SelectFeedIntent.self, provider: FeedProvider()) { entry in
            FeedWidgetView(entry: entry)
        }
        .configurationDisplayName("X Feed")
        .description("Your X timeline, refreshed through the day.")
        .supportedFamilies([.systemMedium, .systemLarge, .systemExtraLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - Configuration

extension FeedKind: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Feed" }
    static var caseDisplayRepresentations: [FeedKind: DisplayRepresentation] {
        [.highlights: "Highlights", .following: "Following"]
    }
}

struct SelectFeedIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Choose Feed" }

    @Parameter(title: "Feed", default: .following)
    var feed: FeedKind
}

struct RefreshFeedIntent: AppIntent {
    static var title: LocalizedStringResource { "Refresh Feed" }

    @Parameter(title: "Feed")
    var feed: FeedKind

    init() {}
    init(feed: FeedKind) { self.feed = feed }

    func perform() async throws -> some IntentResult {
        await FeedRepository.shared.refresh(feed)
        return .result()
    }
}

// MARK: - Timeline

struct FeedEntry: TimelineEntry {
    let date: Date
    let snapshot: FeedSnapshot
}

struct FeedProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FeedEntry {
        FeedEntry(date: .now, snapshot: FeedSnapshot(kind: .following, posts: DemoData.posts(for: .following), updatedAt: .now, status: .demo))
    }

    func snapshot(for configuration: SelectFeedIntent, in context: Context) async -> FeedEntry {
        if context.isPreview {
            return FeedEntry(date: .now, snapshot: FeedSnapshot(kind: configuration.feed, posts: DemoData.posts(for: configuration.feed), updatedAt: .now, status: .demo))
        }
        let snapshot = await FeedRepository.shared.cached(configuration.feed) ?? placeholder(in: context).snapshot
        return FeedEntry(date: .now, snapshot: snapshot)
    }

    func timeline(for configuration: SelectFeedIntent, in context: Context) async -> Timeline<FeedEntry> {
        // If the app polled recently, reuse its cache instead of spending another API read.
        let cached = await FeedRepository.shared.cached(configuration.feed)
        let snapshot: FeedSnapshot
        if let cached, cached.updatedAt.timeIntervalSinceNow > -FeedRepository.freshness {
            snapshot = cached
        } else {
            snapshot = await FeedRepository.shared.refresh(configuration.feed)
        }
        // WidgetKit budgets refreshes; ~15 minutes is the practical floor when the app isn't pushing reloads.
        return Timeline(entries: [FeedEntry(date: .now, snapshot: snapshot)], policy: .after(.now.addingTimeInterval(15 * 60)))
    }
}

// MARK: - View

struct FeedWidgetView: View {
    let entry: FeedEntry
    @Environment(\.widgetFamily) private var family

    private var rowCount: Int {
        switch family {
        case .systemMedium: 2
        case .systemExtraLarge: 10
        default: 5
        }
    }

    var body: some View {
        let snapshot = entry.snapshot
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(snapshot.kind.title).font(.title2.weight(.bold))
                Spacer()
                Button(intent: RefreshFeedIntent(feed: snapshot.kind)) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Text("𝕏").font(.title.weight(.bold))
            }

            if snapshot.posts.isEmpty, let message = snapshot.status.message {
                Spacer()
                Text(message).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
            } else {
                let columns = family == .systemExtraLarge ? [GridItem(.flexible(), spacing: 16), GridItem(.flexible())] : [GridItem(.flexible())]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(snapshot.posts.prefix(rowCount)) { post in
                        Link(destination: openURL(for: post)) {
                            PostRow(post: post, lineLimit: family == .systemExtraLarge ? 3 : 2, avatarSize: 24)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    /// Routed through the app so the post opens in the default browser.
    private func openURL(for post: Post) -> URL {
        var components = URLComponents(string: "xwidget://open")!
        components.queryItems = [URLQueryItem(name: "url", value: post.url.absoluteString)]
        return components.url!
    }
}

#Preview(as: .systemLarge) {
    FeedWidget()
} timeline: {
    FeedEntry(date: .now, snapshot: FeedSnapshot(kind: .following, posts: DemoData.posts(for: .following), updatedAt: .now, status: .demo))
}
