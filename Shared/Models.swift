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

    var url: URL { URL(string: "https://x.com/\(authorHandle)/status/\(id)")! }
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
