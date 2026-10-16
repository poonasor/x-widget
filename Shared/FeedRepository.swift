import Foundation

/// Fetches, merges and caches feeds in the App Group so the app and widget share one source of truth.
actor FeedRepository {
    static let shared = FeedRepository()
    /// Polling accumulates history up to this many posts; scrolling only ever shows cached posts.
    private static let maxPosts = 300
    /// Cached data younger than this is reused instead of spending another API read.
    static let freshness: TimeInterval = 15 * 60

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
        case .highlights:
            // X API v2 has no endpoint for the algorithmic "For You" timeline, so rank the
            // Following timeline instead. It reuses already-fetched posts: no extra API reads.
            var following = cached(.following)
            if following == nil || following!.updatedAt.timeIntervalSinceNow < -Self.freshness {
                following = await refresh(.following)
            }
            guard let following, following.status == .live else {
                throw FeedError(message: following?.status.message ?? "Following feed unavailable.")
            }
            return FeedSnapshot(kind: kind, posts: Self.rankedHighlights(following.posts), updatedAt: following.updatedAt, status: .live)

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

    /// Engagement decayed by age (Hacker News-style), so a fresh post with traction beats an old viral one.
    /// Metrics are as of when each post was first fetched; since_id polling doesn't re-read older posts.
    static func rankedHighlights(_ posts: [Post], now: Date = .now) -> [Post] {
        func score(_ post: Post) -> Double {
            let engagement = Double(post.likeCount + 2 * post.repostCount + post.replyCount)
            let hours = max(0, now.timeIntervalSince(post.createdAt) / 3600)
            return (engagement + 1) / pow(hours + 2, 1.5)
        }
        return posts.sorted { score($0) > score($1) }
    }

    private func save(_ snapshot: FeedSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: cacheURL(snapshot.kind), options: .atomic)
    }

    private func cacheURL(_ kind: FeedKind) -> URL {
        AppGroup.containerURL.appending(path: "feed-\(kind.rawValue).json")
    }
}

private struct FeedError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private extension Array where Element == Post {
    func uniqued() -> [Post] {
        var seen = Set<String>()
        return filter { seen.insert($0.id).inserted }
    }
}
