import Foundation

struct XtreamAccount: Codable {
    let server: URL
    let username: String
    let password: String
}

struct LiveCategory: Decodable, Identifiable {
    let category_id: String
    let category_name: String
    var id: String { category_id }
}

struct LiveStream: Decodable, Identifiable {
    let stream_id: Int
    let name: String
    let stream_icon: String?
    let category_id: String?
    var id: Int { stream_id }
}

enum XtreamError: LocalizedError {
    case invalidServer
    case invalidResponse
    case unauthorized
    var errorDescription: String? {
        switch self {
        case .invalidServer: return "Use a valid HTTPS provider URL."
        case .invalidResponse: return "Provider returned an unexpected response."
        case .unauthorized: return "The provider rejected these credentials."
        }
    }
}

struct XtreamClient {
    let account: XtreamAccount

    private func endpoint(action: String? = nil) throws -> URL {
        guard account.server.scheme?.lowercased() == "https",
              var components = URLComponents(url: account.server, resolvingAgainstBaseURL: false) else {
            throw XtreamError.invalidServer
        }
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !components.path.hasPrefix("/") { components.path = "/" + components.path }
        components.path += "/player_api.php"
        var query = [URLQueryItem(name: "username", value: account.username),
                     URLQueryItem(name: "password", value: account.password)]
        if let action { query.append(URLQueryItem(name: "action", value: action)) }
        components.queryItems = query
        guard let url = components.url else { throw XtreamError.invalidServer }
        return url
    }

    private func fetch<T: Decodable>(_ type: T.Type, action: String? = nil) async throws -> T {
        var request = URLRequest(url: try endpoint(action: action))
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw XtreamError.invalidResponse
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private struct AuthenticationResponse: Decodable {
        struct UserInfo: Decodable { let auth: Int? }
        let user_info: UserInfo?
    }

    func authenticate() async throws {
        let result = try await fetch(AuthenticationResponse.self)
        guard result.user_info?.auth == 1 else { throw XtreamError.unauthorized }
    }

    func categories() async throws -> [LiveCategory] {
        try await fetch([LiveCategory].self, action: "get_live_categories")
    }

    func streams() async throws -> [LiveStream] {
        try await fetch([LiveStream].self, action: "get_live_streams")
    }

    func hlsURL(for stream: LiveStream) throws -> URL {
        var base = account.server
        guard base.scheme?.lowercased() == "https" else { throw XtreamError.invalidServer }
        base.append(path: "live")
        base.append(path: account.username)
        base.append(path: account.password)
        base.append(path: "\(stream.stream_id).m3u8")
        return base
    }
}
