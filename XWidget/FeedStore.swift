import SwiftUI
import WidgetKit

/// Owns live polling for the app. Writes through `FeedRepository` so the widget sees the same data.
@MainActor
@Observable
final class FeedStore {
    private(set) var snapshots: [FeedKind: FeedSnapshot] = [:]
    private(set) var isRefreshing = false
    private var pollTask: Task<Void, Never>?

    init() {
        Task {
            for kind in FeedKind.allCases {
                if let cached = await FeedRepository.shared.cached(kind) { snapshots[kind] = cached }
            }
        }
    }

    func snapshot(_ kind: FeedKind) -> FeedSnapshot {
        snapshots[kind] ?? FeedSnapshot(kind: kind, posts: [], updatedAt: .distantPast, status: .live)
    }

    func start() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAll()
                let interval = max(30, AppGroup.defaults.double(forKey: SettingsKey.pollInterval))
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        var changed = false
        for kind in FeedKind.allCases {
            let fresh = await FeedRepository.shared.refresh(kind)
            if fresh.posts != snapshots[kind]?.posts || fresh.status != snapshots[kind]?.status { changed = true }
            withAnimation(.snappy) { snapshots[kind] = fresh }
        }
        // Reloads requested by the containing app push new data to the widget between its own timeline refreshes.
        if changed { WidgetCenter.shared.reloadAllTimelines() }
    }
}
