import Foundation

struct ChannelCategoryGroup: Identifiable {
    let name: String
    let channels: [PlaylistChannel]
    var id: String { name }
}

/// Channel catalog grouped once at login, so the browser never regroups ~14k channels while rendering.
struct ChannelCatalog {
    static let uncategorized = "Uncategorized"
    static let empty = ChannelCatalog([])

    let all: [PlaylistChannel]
    let groups: [ChannelCategoryGroup]
    private let channelsByCategory: [String: [PlaylistChannel]]

    /// Categories follow `preferredOrder` (Xtream provider order), then first appearance in the
    /// list (M3U order). `Uncategorized` is always last.
    init(_ channels: [PlaylistChannel], preferredOrder: [String] = []) {
        all = channels
        var buckets: [String: [PlaylistChannel]] = [:]
        var appearance: [String] = []
        for channel in channels {
            if buckets[channel.category] == nil { appearance.append(channel.category) }
            buckets[channel.category, default: []].append(channel)
        }
        var ordered: [String] = []
        var seen = Set<String>()
        for name in preferredOrder + appearance {
            guard name != Self.uncategorized, buckets[name] != nil, seen.insert(name).inserted else { continue }
            ordered.append(name)
        }
        if buckets[Self.uncategorized] != nil { ordered.append(Self.uncategorized) }
        channelsByCategory = buckets
        groups = ordered.map { ChannelCategoryGroup(name: $0, channels: buckets[$0] ?? []) }
    }

    func channels(in category: String) -> [PlaylistChannel] {
        channelsByCategory[category] ?? []
    }
}
