import Foundation
import CryptoKit

/// TV guide from an XMLTV file (the "EPG URL" of M3U providers, plain or .gz).
/// Downloaded in the background, trimmed to the next ~36 hours, saved on the device
/// (refreshed every 12 hours) and matched to channels by tvg-id / epg_channel_id or name.
final class XMLTVGuide: ObservableObject {
    static let shared = XMLTVGuide()

    enum Status: Equatable {
        case none
        case loading
        case ready(channels: Int, updated: Date)
        case failed(String)
    }

    @Published private(set) var status: Status = .none
    /// Bumped when a guide loads so open players look again.
    @Published private(set) var revision = 0

    private var index = GuideIndex.empty
    private var loadedKey: String?
    private var loading = false
    private static let maxAge: TimeInterval = 12 * 3600

    private static var folder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("veylo-guide", isDirectory: true)
    }

    // MARK: Lookup

    func programmes(for channel: PlaylistChannel) -> [EPGProgram] {
        guard !index.programmes.isEmpty else { return [] }
        var list: [GuideProgramme]?
        if let id = channel.epgID?.lowercased() { list = index.programmes[id] }
        if list == nil {
            for name in [channel.epgName, channel.title, channel.name].compactMap({ $0 }) {
                let key = LogoDirectory.key(name)
                if let id = index.names[key], let found = index.programmes[id] {
                    list = found
                    break
                }
            }
        }
        let now = Date().timeIntervalSince1970
        return (list ?? [])
            .filter { $0.end > now }
            .prefix(6)
            .map { EPGProgram(title: $0.title, summary: $0.summary,
                              start: Date(timeIntervalSince1970: $0.start), end: Date(timeIntervalSince1970: $0.end)) }
    }

    // MARK: Loading

    @MainActor func reset() {
        index = .empty
        loadedKey = nil
        status = .none
        revision += 1
    }

    @MainActor func load(url: URL?, force: Bool = false) async {
        guard let url else {
            reset()
            return
        }
        guard !loading else { return }
        let key = SHA256.hash(data: Data(url.absoluteString.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        if !force, loadedKey == key, case .ready(_, let updated) = status,
           Date().timeIntervalSince(updated) < Self.maxAge { return }
        loading = true
        defer { loading = false }
        status = .loading
        let file = Self.folder.appendingPathComponent(key + ".json")

        if !force, let saved = await Task.detached(priority: .utility, operation: { Self.readSaved(file) }).value,
           Date().timeIntervalSince(saved.date) < Self.maxAge {
            apply(saved.index, key: key, updated: saved.date)
            return
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 120
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            let built = await Task.detached(priority: .utility) { () -> GuideIndex in
                let index = XMLTVParser.parse(Self.gunzipIfNeeded(data))
                if !index.programmes.isEmpty { Self.save(index, to: file) }
                return index
            }.value
            guard !built.programmes.isEmpty else {
                status = .failed("The guide file had no programmes for the coming hours.")
                return
            }
            apply(built, key: key, updated: Date())
        } catch {
            if let saved = await Task.detached(priority: .utility, operation: { Self.readSaved(file) }).value {
                apply(saved.index, key: key, updated: saved.date)
            } else {
                status = .failed(error.localizedDescription)
            }
        }
    }

    @MainActor private func apply(_ newIndex: GuideIndex, key: String, updated: Date) {
        index = newIndex
        loadedKey = key
        status = .ready(channels: newIndex.programmes.count, updated: updated)
        revision += 1
    }

    // MARK: Files

    private static func readSaved(_ file: URL) -> (index: GuideIndex, date: Date)? {
        guard let data = try? Data(contentsOf: file),
              let index = try? JSONDecoder().decode(GuideIndex.self, from: data) else { return nil }
        let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        return (index, date)
    }

    private static func save(_ index: GuideIndex, to file: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(index) { try? data.write(to: file, options: .atomic) }
    }

    static func clearSaved() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Unwraps a gzip (.gz) download; plain XML is returned as is.
    static func gunzipIfNeeded(_ input: Data) -> Data {
        let data = Data(input)
        guard data.count > 18, data[0] == 0x1f, data[1] == 0x8b, data[2] == 8 else { return data }
        let flags = data[3]
        var position = 10
        if flags & 0x04 != 0, data.count > position + 2 {
            position += 2 + (Int(data[position]) | Int(data[position + 1]) << 8)
        }
        if flags & 0x08 != 0 {
            while position < data.count, data[position] != 0 { position += 1 }
            position += 1
        }
        if flags & 0x10 != 0 {
            while position < data.count, data[position] != 0 { position += 1 }
            position += 1
        }
        if flags & 0x02 != 0 { position += 2 }
        guard position < data.count - 8 else { return data }
        let deflated = data.subdata(in: position..<(data.count - 8)) as NSData
        return (try? deflated.decompressed(using: .zlib) as Data) ?? data
    }
}

struct GuideProgramme: Codable {
    let title: String
    let summary: String?
    let start: Double
    let end: Double
}

struct GuideIndex: Codable {
    static let empty = GuideIndex(programmes: [:], names: [:])
    /// lowercased XMLTV channel id → programmes (sorted)
    let programmes: [String: [GuideProgramme]]
    /// cleaned display name → lowercased channel id
    let names: [String: String]
}

/// Streaming XMLTV parser; keeps only programmes from 2 hours ago to 36 hours ahead.
private final class XMLTVParser: NSObject, XMLParserDelegate {
    private var programmes: [String: [GuideProgramme]] = [:]
    private var names: [String: String] = [:]
    private let windowStart = Date().addingTimeInterval(-2 * 3600).timeIntervalSince1970
    private let windowEnd = Date().addingTimeInterval(36 * 3600).timeIntervalSince1970

    private var channelID: String?
    private var programmeChannel: String?
    private var programmeStart: Double?
    private var programmeEnd: Double?
    private var title: String?
    private var summary: String?
    private var text = ""
    private var collecting = false

    private let zoned: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMddHHmmss Z"
        return formatter
    }()
    private let plain: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMddHHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    static func parse(_ data: Data) -> GuideIndex {
        let delegate = XMLTVParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        parser.parse()
        var sorted: [String: [GuideProgramme]] = [:]
        for (id, list) in delegate.programmes {
            sorted[id] = Array(list.sorted { $0.start < $1.start }.prefix(60))
        }
        let names = delegate.names.filter { sorted[$0.value] != nil }
        return GuideIndex(programmes: sorted, names: names)
    }

    private func date(_ raw: String?) -> Double? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), raw.count >= 14 else { return nil }
        if raw.count > 14, let value = zoned.date(from: raw) { return value.timeIntervalSince1970 }
        return plain.date(from: String(raw.prefix(14)))?.timeIntervalSince1970
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        switch elementName {
        case "channel":
            channelID = attributes["id"]?.lowercased()
        case "display-name":
            collecting = channelID != nil
            text = ""
        case "programme":
            programmeChannel = attributes["channel"]?.lowercased()
            programmeEnd = date(attributes["stop"])
            programmeStart = date(attributes["start"])
            title = nil
            summary = nil
        case "title", "desc":
            collecting = programmeChannel != nil
            text = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if collecting { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "display-name":
            if let channelID {
                let key = LogoDirectory.key(text)
                if key.count >= 2, names[key] == nil { names[key] = channelID }
            }
            collecting = false
        case "channel":
            channelID = nil
        case "title":
            if title == nil { title = text.trimmingCharacters(in: .whitespacesAndNewlines) }
            collecting = false
        case "desc":
            if summary == nil { summary = text.trimmingCharacters(in: .whitespacesAndNewlines) }
            collecting = false
        case "programme":
            if let id = programmeChannel, let start = programmeStart, let end = programmeEnd,
               end > start, end > windowStart, start < windowEnd,
               let title, !title.isEmpty {
                programmes[id, default: []].append(GuideProgramme(
                    title: title,
                    summary: summary.flatMap { $0.isEmpty ? nil : String($0.prefix(400)) },
                    start: start, end: end))
            }
            programmeChannel = nil
        default:
            break
        }
    }
}
