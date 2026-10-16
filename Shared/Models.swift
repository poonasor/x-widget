import Foundation

enum FeedKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case highlights
    case following

    var id: String { rawValue }

    var title: String {
        switch self {
        case .highlights: "Highlights"
        case .following: "Following"
        }
    }
}

struct Post: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let text: String
    let createdAt: Date
    let authorID: String
    let authorName: String
    let authorHandle: String
    let avatarURL: URL?
    let likeCount: Int
    let replyCount: Int
    let repostCount: Int
    /// The original post's ID when this is a repost. Optional so older caches still decode.
    var repostOfID: String? = nil
    var replyToID: String? = nil
    /// Photos, or thumbnails for videos and GIFs. Optional so older caches still decode.
    var media: [PostMedia]? = nil

    var isRepost: Bool { repostOfID != nil || text.hasPrefix("RT @") }
    var isReply: Bool { replyToID != nil }

    var url: URL { URL(string: "https://x.com/\(authorHandle)/status/\(id)")! }
}

struct PostMedia: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case photo, video, gif }

    let kind: Kind
    /// The photo itself, or the preview frame for videos and GIFs.
    let imageURL: URL
    let width: Int?
    let height: Int?
    let altText: String?

    /// pbs.twimg.com serves resized variants via `name=`; "small" (≤680px) is plenty for a sidebar.
    var smallImageURL: URL {
        guard var components = URLComponents(url: imageURL, resolvingAgainstBaseURL: false),
              components.host == "pbs.twimg.com" else { return imageURL }
        components.queryItems = (components.queryItems ?? []).filter { $0.name != "name" } + [URLQueryItem(name: "name", value: "small")]
        return components.url ?? imageURL
    }

    var aspectRatio: CGFloat? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return CGFloat(width) / CGFloat(height)
    }
}

enum FeedStatus: Codable, Hashable, Sendable {
    case live
    case demo
    case signedOut
    case unavailable(String)
    case error(String)

    var message: String? {
        switch self {
        case .live: nil
        case .demo: "Demo data — add your X Client ID in Settings."
        case .signedOut: "Sign in to X in Settings."
        case .unavailable(let reason), .error(let reason): reason
        }
    }
}

struct FeedSnapshot: Codable, Hashable, Sendable {
    var kind: FeedKind
    var posts: [Post]
    var updatedAt: Date
    var status: FeedStatus
}
