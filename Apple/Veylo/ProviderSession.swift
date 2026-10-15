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

    /// Now/next programmes for an Xtream live channel (empty for M3U or when the provider has no guide).
    func programmes(for channel: PlaylistChannel) async -> [EPGProgram] {
        guard let client, channel.key.hasPrefix("x:"), let id = Int(channel.key.dropFirst(2)) else { return [] }
        let zone = await MainActor.run { account?.timeZone }
        return (try? await client.shortEPG(streamID: id, timeZone: zone)) ?? []
    }
}
