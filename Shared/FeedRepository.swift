import Foundation

/// Fetches, merges and caches feeds in the App Group so the app and widget share one source of truth.
actor FeedRepository {
    static let shared = FeedRepository()
    private static let maxPosts = 60

    func cached(_ kind: FeedKind) -> FeedSnapshot? {
        guard let data = try? Data(contentsOf: cacheURL(kind)) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(FeedSnapshot.self, from: data)
    }

    @discardableResult
    func refresh(_ kind: FeedKind) async -> FeedSnapshot {
        let previous = cached(kind)
        let snapshot: FeedSnapshot
        do {
            snapshot = try await fetch(kind, previous: previous)
        } catch {
            snapshot = FeedSnapshot(
                kind: kind,
                posts: previous?.posts ?? [],
                updatedAt: previous?.updatedAt ?? .now,
                status: .error(error.localizedDescription)
            )
        }
        await AvatarStore.prefetch(snapshot.posts)
        save(snapshot)
        return snapshot
    }

    private func fetch(_ kind: FeedKind, previous: FeedSnapshot?) async throws -> FeedSnapshot {
        guard XAuth.clientID != nil else {
            return FeedSnapshot(kind: kind, posts: DemoData.posts(for: kind), updatedAt: .now, status: .demo)
        }
        guard var token = try await XAuth.validToken() else {
            return FeedSnapshot(kind: kind, posts: [], updatedAt: .now, status: .signedOut)
        }

        switch kind {
        case .forYou:
            // X API v2 exposes no endpoint for the algorithmic "For You" timeline.
            return FeedSnapshot(
                kind: kind, posts: [], updatedAt: .now,
                status: .unavailable("X's public API doesn't offer the For You timeline.")
            )

        case .following:
            let client = XAPIClient(accessToken: token.accessToken)
            if token.userID == nil {
                token.userID = try await client.currentUserID()
                TokenStore.save(token)
            }
            let livePrevious = previous?.status == .live ? previous?.posts ?? [] : []
            // since_id keeps reads (and API credits) to only new posts.
            let fresh = try await client.homeTimeline(userID: token.userID!, sinceID: livePrevious.first?.id)
            let merged = Array((fresh + livePrevious).uniqued().prefix(Self.maxPosts))
            return FeedSnapshot(kind: kind, posts: merged, updatedAt: .now, status: .live)
        }
    }

    private func save(_ snapshot: FeedSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: cacheURL(snapshot.kind), options: .atomic)
    }

    private func cacheURL(_ kind: FeedKind) -> URL {
        AppGroup.containerURL.appending(path: "feed-\(kind.rawValue).json")
    }
}

private extension Array where Element == Post {
    func uniqued() -> [Post] {
        var seen = Set<String>()
        return filter { seen.insert($0.id).inserted }
    }
}
