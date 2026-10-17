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

    private enum CodingKeys: String, CodingKey { case category_id, category_name }

    /// Lenient: ids may arrive as numbers or strings; rows without an id are skipped.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = (try? container.decodeIfPresent(XtreamFlex.self, forKey: .category_id))?.string else {
            throw XtreamFlex.Missing()
        }
        category_id = id
        category_name = (try? container.decodeIfPresent(XtreamFlex.self, forKey: .category_name))?.string ?? "Other"
    }
}

struct LiveStream: Decodable, Identifiable {
    let stream_id: Int
    let name: String
    let stream_icon: String?
    let category_id: String?
    /// XMLTV channel id used by the provider's guide, when given.
    let epg_channel_id: String?
    var id: Int { stream_id }

    private enum CodingKeys: String, CodingKey { case stream_id, name, stream_icon, category_id, epg_channel_id }

    /// Lenient: numbers may arrive as strings (and the reverse), names may be null;
    /// a row without a usable stream id is skipped instead of failing the whole login.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = (try? container.decodeIfPresent(XtreamFlex.self, forKey: .stream_id))?.int else {
            throw XtreamFlex.Missing()
        }
        stream_id = id
        name = (try? container.decodeIfPresent(XtreamFlex.self, forKey: .name))?.string ?? "Channel \(id)"
        stream_icon = (try? container.decodeIfPresent(XtreamFlex.self, forKey: .stream_icon))?.string
        category_id = (try? container.decodeIfPresent(XtreamFlex.self, forKey: .category_id))?.string
        epg_channel_id = (try? container.decodeIfPresent(XtreamFlex.self, forKey: .epg_channel_id))?.string
    }
}

/// A JSON value that may be a string, number, bool or null.
struct XtreamFlex: Decodable {
    struct Missing: Error {}

    let string: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            string = nil
        } else if let text = try? container.decode(String.self) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            string = trimmed.isEmpty ? nil : trimmed
        } else if let number = try? container.decode(Int.self) {
            string = String(number)
        } else if let number = try? container.decode(Double.self) {
            string = number == number.rounded() && abs(number) < 1e15 ? String(Int(number)) : String(number)
        } else if let flag = try? container.decode(Bool.self) {
            string = flag ? "1" : "0"
        } else {
            string = nil
        }
    }

    var int: Int? {
        guard let string else { return nil }
        if let value = Int(string) { return value }
        return Double(string).map { Int($0) }
    }
}

/// A JSON list (or id-keyed object) where bad rows are skipped instead of failing the whole response.
struct XtreamList<Element: Decodable>: Decodable {
    let items: [Element]

    private struct Skip: Decodable { init(from decoder: Decoder) throws {} }

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
    }

    init(from decoder: Decoder) throws {
        if var list = try? decoder.unkeyedContainer() {
            var result: [Element] = []
            while !list.isAtEnd {
                if let value = try? list.decode(Element.self) {
                    result.append(value)
                } else if (try? list.decode(Skip.self)) == nil {
                    break
                }
            }
            items = result
        } else if let object = try? decoder.container(keyedBy: AnyKey.self) {
            items = object.allKeys.compactMap { try? object.decode(Element.self, forKey: $0) }
        } else {
            items = []
        }
    }
}

enum XtreamError: LocalizedError {
    case invalidServer
    case invalidResponse
    case unauthorized
    var errorDescription: String? {
        switch self {
        case .invalidServer: return "Use a valid HTTP or HTTPS provider URL."
        case .invalidResponse: return "Provider returned an unexpected response."
        case .unauthorized: return "The provider rejected these credentials."
        }
    }
}

struct XtreamClient {
    let account: XtreamAccount

    private func endpoint(action: String? = nil) throws -> URL {
        guard ["http", "https"].contains(account.server.scheme?.lowercased() ?? ""),
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
        struct UserInfo: Decodable {
            let auth: XtreamFlex?
        }
        let user_info: UserInfo?
    }

    func authenticate() async throws {
        let result: AuthenticationResponse
        do {
            result = try await fetch(AuthenticationResponse.self)
        } catch is DecodingError {
            // HTML or other non-JSON page instead of the API answer.
            throw XtreamError.invalidResponse
        }
        guard result.user_info?.auth?.int == 1 else { throw XtreamError.unauthorized }
    }

    func categories() async throws -> [LiveCategory] {
        try await fetch(XtreamList<LiveCategory>.self, action: "get_live_categories").items
    }

    func streams() async throws -> [LiveStream] {
        try await fetch(XtreamList<LiveStream>.self, action: "get_live_streams").items
    }

    func streamURL(for stream: LiveStream, extension ext: String = "m3u8") throws -> URL {
        var base = account.server
        guard ["http", "https"].contains(base.scheme?.lowercased() ?? "") else { throw XtreamError.invalidServer }
        base.append(path: "live")
        base.append(path: account.username)
        base.append(path: account.password)
        base.append(path: "\(stream.stream_id).\(ext)")
        return base
    }
}
