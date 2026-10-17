import Foundation

/// The signed-in Xtream provider for features outside the live catalog:
/// subscription status (Settings, player failure hints) and the TV guide (EPG).
final class ProviderSession: ObservableObject {
    static let shared = ProviderSession()

    @Published private(set) var account: ProviderAccountInfo?
    @Published private(set) var accountError: String?
    @Published private(set) var loadingAccount = false
    private(set) var client: XtreamClient?

    var hasProvider: Bool { client != nil }

    @MainActor func start(client: XtreamClient?) {
        if let client, client.cacheIdentity == self.client?.cacheIdentity { return }
        self.client = client
        account = nil
        accountError = nil
    }

    @MainActor func reset() {
        client = nil
        account = nil
        accountError = nil
    }

    @MainActor func refreshAccount() async {
        guard let client, !loadingAccount else { return }
        loadingAccount = true
        defer { loadingAccount = false }
        do {
            account = try await client.accountInfo()
            accountError = nil
        } catch {
            accountError = error.localizedDescription
        }
    }

    /// Now/next programmes: the Xtream guide first, then the XMLTV guide (M3U "EPG URL").
    func programmes(for channel: PlaylistChannel) async -> [EPGProgram] {
        if let client, channel.key.hasPrefix("x:"), let id = Int(channel.key.dropFirst(2)) {
            let zone = await MainActor.run { account?.timeZone }
            let list = (try? await client.shortEPG(streamID: id, timeZone: zone)) ?? []
            if !list.isEmpty { return list }
        }
        return await MainActor.run { XMLTVGuide.shared.programmes(for: channel) }
    }
}
