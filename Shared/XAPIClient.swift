import Foundation

enum XAPIError: LocalizedError {
    case unauthorized
    case rateLimited(resetAt: Date?)
    case paymentRequired
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: "X session expired — sign in again."
        case .rateLimited(let reset):
            reset.map { "Rate limited until \($0.formatted(date: .omitted, time: .shortened))." } ?? "Rate limited."
        case .paymentRequired: "Your X API project is out of credits or lacks read access."
        case .http(let code, let body): "X API error \(code): \(body.prefix(140))"
        }
    }
}

/// Minimal X API v2 client. Docs: https://docs.x.com/x-api
struct XAPIClient: Sendable {
    static let base = URL(string: "https://api.x.com/2")!
    let accessToken: String

    func currentUserID() async throws -> String {
        struct Me: Decodable { struct D: Decodable { let id: String }; let data: D }
        let me: Me = try await get("users/me", query: [])
        return me.data.id
    }

    /// The "Following" feed: reverse-chronological home timeline.
    func homeTimeline(userID: String, sinceID: String?, maxResults: Int = 30) async throws -> [Post] {
        var query = [
            URLQueryItem(name: "max_results", value: String(maxResults)),
            URLQueryItem(name: "exclude", value: "replies"),
            URLQueryItem(name: "expansions", value: "author_id"),
            URLQueryItem(name: "tweet.fields", value: "created_at,public_metrics,author_id,note_tweet"),
            URLQueryItem(name: "user.fields", value: "name,username,profile_image_url"),
        ]
        if let sinceID { query.append(URLQueryItem(name: "since_id", value: sinceID)) }
        let page: TimelinePage = try await get("users/\(userID)/timelines/reverse_chronological", query: query)
        return page.posts
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> T {
        var components = URLComponents(url: Self.base.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as! HTTPURLResponse
        switch http.statusCode {
        case 200..<300: break
        case 401: throw XAPIError.unauthorized
        case 402: throw XAPIError.paymentRequired
        case 429:
            let reset = (http.value(forHTTPHeaderField: "x-rate-limit-reset")).flatMap(TimeInterval.init)
            throw XAPIError.rateLimited(resetAt: reset.map(Date.init(timeIntervalSince1970:)))
        default: throw XAPIError.http(http.statusCode, String(decoding: data, as: UTF8.self))
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            return (try? Date(string, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)))
                ?? (try? Date(string, strategy: .iso8601))
                ?? .now
        }
        return try decoder.decode(T.self, from: data)
    }
}

private struct TimelinePage: Decodable {
    struct Tweet: Decodable {
        struct Metrics: Decodable { let like_count: Int; let reply_count: Int; let retweet_count: Int }
        struct NoteTweet: Decodable { let text: String }
        let id: String
        let text: String
        let author_id: String
        let created_at: Date
        let public_metrics: Metrics?
        let note_tweet: NoteTweet?
    }
    struct User: Decodable { let id: String; let name: String; let username: String; let profile_image_url: URL? }
    struct Includes: Decodable { let users: [User]? }

    let data: [Tweet]?
    let includes: Includes?

    var posts: [Post] {
        let users = Dictionary((includes?.users ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return (data ?? []).map { tweet in
            let user = users[tweet.author_id]
            return Post(
                id: tweet.id,
                text: (tweet.note_tweet?.text ?? tweet.text).decodingHTMLEntities,
                createdAt: tweet.created_at,
                authorID: tweet.author_id,
                authorName: user?.name ?? "Unknown",
                authorHandle: user?.username ?? "i",
                avatarURL: user?.profile_image_url,
                likeCount: tweet.public_metrics?.like_count ?? 0,
                replyCount: tweet.public_metrics?.reply_count ?? 0,
                repostCount: tweet.public_metrics?.retweet_count ?? 0
            )
        }
    }
}

private extension String {
    var decodingHTMLEntities: String {
        replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}
