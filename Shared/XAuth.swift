import Foundation

/// OAuth 2.0 (PKCE, public client) helpers shared by the app and the widget.
/// The interactive sign-in lives in the app target (`SignInController`).
enum XAuth {
    static let authorizeURL = URL(string: "https://x.com/i/oauth2/authorize")!
    static let tokenURL = URL(string: "https://api.x.com/2/oauth2/token")!
    static let redirectURI = "xwidget://oauth/callback"
    static let scopes = "tweet.read users.read offline.access"

    static var clientID: String? {
        let id = AppGroup.defaults.string(forKey: SettingsKey.clientID)?.trimmingCharacters(in: .whitespaces)
        return (id?.isEmpty ?? true) ? nil : id
    }

    /// Returns a valid token, refreshing it if it's about to expire.
    static func validToken() async throws -> XToken? {
        guard var token = TokenStore.load() else { return nil }
        if token.isExpiring {
            guard let refresh = token.refreshToken, let clientID else { throw XAPIError.unauthorized }
            let fresh = try await requestToken([
                "grant_type": "refresh_token",
                "refresh_token": refresh,
                "client_id": clientID,
            ])
            token.accessToken = fresh.accessToken
            token.refreshToken = fresh.refreshToken ?? refresh
            token.expiresAt = fresh.expiresAt
            TokenStore.save(token)
        }
        return token
    }

    static func requestToken(_ form: [String: String]) async throws -> XToken {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw XAPIError.http((response as? HTTPURLResponse)?.statusCode ?? 0, String(decoding: data, as: UTF8.self))
        }
        struct Response: Decodable { let access_token: String; let refresh_token: String?; let expires_in: Double }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return XToken(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token,
            expiresAt: .now.addingTimeInterval(decoded.expires_in),
            userID: nil
        )
    }
}
