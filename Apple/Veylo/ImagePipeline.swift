import SwiftUI
import UIKit
import ImageIO
import CryptoKit

/// Image loader for posters, backdrops and channel logos.
/// - Memory cache of decoded, downsized images (smooth scrolling back and forth)
/// - Disk cache that survives app restarts (no re-downloading)
/// - Downsizing to display size (big provider images load and decode much faster)
/// - Downloads keep going when a tile scrolls away, and failed downloads are retried
actor ImagePipeline {
    static let shared = ImagePipeline()

    private static let memory = ImageMemoryCache()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private let session: URLSession
    private let browserSession: URLSession
    private let directory: URL
    private static let diskLimit = 400 * 1024 * 1024

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 8
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 180
        session = URLSession(configuration: configuration)
        // Some image hosts only answer browser-like requests; used for the second attempt.
        let browser = configuration.copy() as! URLSessionConfiguration
        browser.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        ]
        browserSession = URLSession(configuration: browser)
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("veylo-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let folder = directory
        Task.detached(priority: .background) { Self.prune(folder) }
    }

    /// Already-decoded image, for showing instantly without a placeholder flash.
    nonisolated func memoryImage(for url: URL, maxPixel: CGFloat) -> UIImage? {
        Self.memory.image(forKey: Self.key(url, maxPixel))
    }

    func image(for url: URL, maxPixel: CGFloat) async -> UIImage? {
        let key = Self.key(url, maxPixel)
        if let cached = Self.memory.image(forKey: key) { return cached }
        if let running = inFlight[key] { return await running.value }

        let file = directory.appendingPathComponent(key)
        let source = Self.optimized(url, maxPixel: maxPixel)
        let sessions = [self.session, self.browserSession, self.session]
        let task = Task.detached(priority: .utility) { () -> UIImage? in
            if let data = try? Data(contentsOf: file), let image = Self.downsample(data, maxPixel: maxPixel) {
                return image
            }
            for attempt in 0..<3 {
                if attempt > 0 { try? await Task.sleep(nanoseconds: UInt64(attempt) * 800_000_000) }
                guard let result = try? await sessions[attempt].data(from: source) else { continue }
                let (data, response) = result
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    if http.statusCode == 404 { return nil }
                    continue
                }
                guard let image = Self.downsample(data, maxPixel: maxPixel) else { return nil }
                Self.store(image, at: file)
                return image
            }
            return nil
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image {
            Self.memory.insert(image, forKey: key)
        }
        return image
    }

    func clear() {
        Self.memory.removeAll()
        inFlight.removeAll()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: Helpers

    private static func key(_ url: URL, _ maxPixel: CGFloat) -> String {
        let digest = SHA256.hash(data: Data("\(url.absoluteString)@\(Int(maxPixel))".utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// TMDB artwork is often linked at original size (several MB); ask for a size that fits the screen.
    private static func optimized(_ url: URL, maxPixel: CGFloat) -> URL {
        guard url.host?.lowercased().hasSuffix("tmdb.org") == true,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var parts = components.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 4, parts[0] == "t", parts[1] == "p" else { return url }
        parts[2] = maxPixel <= 200 ? "w185" : maxPixel <= 400 ? "w342" : maxPixel <= 600 ? "w500" : maxPixel <= 900 ? "w780" : "w1280"
        components.path = "/" + parts.joined(separator: "/")
        return components.url ?? url
    }

    private static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return UIImage(data: data)
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return UIImage(data: data) }
        return UIImage(cgImage: image)
    }

    private static func store(_ image: UIImage, at file: URL) {
        let alpha = image.cgImage?.alphaInfo ?? .none
        let opaque = alpha == .none || alpha == .noneSkipFirst || alpha == .noneSkipLast
        let data = opaque ? image.jpegData(compressionQuality: 0.85) : image.pngData()
        try? data?.write(to: file, options: .atomic)
    }

    /// Keeps the disk cache under its limit by removing the least recently written files.
    private static func prune(_ folder: URL) {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { return }
        var entries: [(url: URL, date: Date, size: Int)] = files.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, values.contentModificationDate ?? .distantPast, values.fileSize ?? 0)
        }
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > diskLimit else { return }
        entries.sort { $0.date < $1.date }
        for entry in entries where total > diskLimit * 3 / 4 {
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
    }
}

/// Thread-safe decoded-image cache (NSCache is internally synchronized).
final class ImageMemoryCache: @unchecked Sendable {
    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 120 * 1024 * 1024
        return cache
    }()

    func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func insert(_ image: UIImage, forKey key: String) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}

/// Cached remote image with an optional placeholder shown until it loads (or if it fails).
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    let maxPixel: CGFloat
    let contentMode: ContentMode
    let placeholder: Placeholder

    @State private var image: UIImage?

    init(url: URL?, maxPixel: CGFloat = 540, contentMode: ContentMode = .fill,
         @ViewBuilder placeholder: () -> Placeholder) {
        self.url = url
        self.maxPixel = maxPixel
        self.contentMode = contentMode
        self.placeholder = placeholder()
        _image = State(initialValue: url.flatMap { ImagePipeline.shared.memoryImage(for: $0, maxPixel: maxPixel) })
    }

    var body: some View {
        Group {
            if contentMode == .fill {
                Color.clear
                    .overlay { content }
                    .clipped()
            } else {
                content
            }
        }
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            if let cached = ImagePipeline.shared.memoryImage(for: url, maxPixel: maxPixel) {
                image = cached
                return
            }
            image = nil
            let loaded = await ImagePipeline.shared.image(for: url, maxPixel: maxPixel)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }

    @ViewBuilder private var content: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else {
            placeholder
        }
    }
}

extension RemoteImage where Placeholder == EmptyView {
    init(url: URL?, maxPixel: CGFloat = 540, contentMode: ContentMode = .fill) {
        self.init(url: url, maxPixel: maxPixel, contentMode: contentMode) { EmptyView() }
    }
}
