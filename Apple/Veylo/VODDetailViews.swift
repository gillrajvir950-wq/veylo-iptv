import SwiftUI

// MARK: - Shared header

/// Backdrop (or blurred poster) with the poster card, fading into black.
private struct DetailHeader: View {
    let backdrop: URL?
    let poster: URL?
    let title: String
    let kind: VODItem.Kind

    var body: some View {
        ZStack(alignment: .bottom) {
            if let backdrop {
                PosterImage(url: backdrop, maxPixel: 1200)
            } else {
                PosterImage(url: poster)
                    .blur(radius: 40)
                    .opacity(0.6)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.6), .black], startPoint: .top, endPoint: .bottom)
            if backdrop == nil {
                PosterArtwork(url: poster, title: title, kind: kind)
                    .frame(width: 150)
                    .shadow(color: .black.opacity(0.7), radius: 16, y: 8)
                    .padding(.bottom, 8)
            }
        }
        .frame(height: 330)
        .frame(maxWidth: .infinity)
        .clipped()
    }
}

private struct InfoRow: View {
    let label: String
    let value: String?

    var body: some View {
        if let value, !value.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(VeyloTheme.textTertiary)
                Text(value)
                    .font(.system(size: 14))
                    .foregroundStyle(VeyloTheme.textSecondary)
            }
        }
    }
}

private struct CloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(.black.opacity(0.55), in: Circle())
        }
        .buttonStyle(VeyloPressStyle(scale: 0.9))
        .padding(16)
        .accessibilityLabel("Close")
    }
}

private func primaryLabel(_ title: String, icon: String) -> some View {
    HStack(spacing: 8) {
        Image(systemName: icon).font(.system(size: 14, weight: .bold))
        Text(title)
    }
    .font(.system(size: 17, weight: .semibold))
    .foregroundStyle(.black)
    .frame(maxWidth: .infinity)
    .frame(height: 50)
    .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
}

private func secondaryLabel(_ title: String, icon: String) -> some View {
    VStack(spacing: 5) {
        Image(systemName: icon).font(.system(size: 18, weight: .semibold))
        Text(title).font(.system(size: 11, weight: .medium))
    }
    .foregroundStyle(.white)
    .frame(width: 76, height: 50)
    .background(VeyloTheme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
}

private func metaLine(_ parts: [String?]) -> some View {
    Text(parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "  ·  "))
        .font(.system(size: 14))
        .foregroundStyle(VeyloTheme.textSecondary)
}

// MARK: - Movie

struct MovieDetailView: View {
    let item: VODItem
    let client: XtreamClient

    @Environment(\.dismiss) private var dismiss
    @AppStorage(LibraryKeys.movieList) private var myListRaw = ""
    @AppStorage(VODProgressStore.defaultsKey) private var progressData = Data()
    @State private var details: MovieDetails?
    @State private var loading = true
    @State private var playRequest: VODPlayRequest?
    @State private var errorText: String?

    private var progress: VODProgressEntry? { VODProgressStore.decode(progressData)[item.key] }
    private var inList: Bool { KeyList.split(myListRaw).contains(item.key) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DetailHeader(backdrop: details?.backdropURL, poster: details?.posterURL ?? item.posterURL,
                             title: item.title, kind: .movie)
                VStack(alignment: .leading, spacing: 16) {
                    Text(item.title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                    metaLine([item.year, details?.duration, details?.genre,
                              (details?.rating ?? item.rating).map { "★ " + String(format: "%.1f", $0) }])
                    HStack(spacing: 10) {
                        Button { play(from: progress?.position ?? 0) } label: {
                            if let progress {
                                primaryLabel("Resume · \(progress.remainingMinutes) min left", icon: "play.fill")
                            } else {
                                primaryLabel("Play", icon: "play.fill")
                            }
                        }
                        .buttonStyle(VeyloPressStyle())
                        if progress != nil {
                            Button { play(from: 0) } label: {
                                secondaryLabel("Restart", icon: "gobackward")
                            }
                            .buttonStyle(VeyloPressStyle())
                        }
                        Button { myListRaw = KeyList.toggled(item.key, in: myListRaw) } label: {
                            secondaryLabel("My List", icon: inList ? "checkmark" : "plus")
                        }
                        .buttonStyle(VeyloPressStyle())
                    }
                    .padding(.top, 4)
                    if let progress {
                        ProgressView(value: progress.fraction).tint(.white)
                    }
                    if let plot = details?.plot {
                        Text(plot)
                            .font(.system(size: 15))
                            .foregroundStyle(VeyloTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if loading {
                        ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        InfoRow(label: "Cast", value: details?.cast)
                        InfoRow(label: "Director", value: details?.director)
                        InfoRow(label: "Released", value: details?.released)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
            }
            .padding(.bottom, 40)
        }
        .ignoresSafeArea(edges: .top)
        .background(Color.black)
        .overlay(alignment: .topTrailing) { CloseButton { dismiss() } }
        .task {
            details = try? await client.movieDetails(id: item.id)
            loading = false
        }
        .fullScreenCover(item: $playRequest) { request in
            VODPlayerView(request: request)
        }
        .alert("Veylo", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK") { errorText = nil }
        } message: { Text(errorText ?? "") }
    }

    private func play(from start: Double) {
        do {
            playRequest = VODPlayRequest(url: try client.movieURL(for: item), title: item.title,
                                         subtitle: item.meta, progressKey: item.key, startAt: start)
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Series

struct SeriesDetailView: View {
    let item: VODItem
    let client: XtreamClient

    @Environment(\.dismiss) private var dismiss
    @AppStorage(LibraryKeys.seriesList) private var myListRaw = ""
    @AppStorage(LibraryKeys.recentSeries) private var recentSeriesRaw = ""
    @AppStorage(VODProgressStore.defaultsKey) private var progressData = Data()
    @State private var details: SeriesDetails?
    @State private var loading = true
    @State private var loadError: String?
    @State private var season = 1
    @State private var playRequest: VODPlayRequest?

    private var progress: [String: VODProgressEntry] { VODProgressStore.decode(progressData) }
    private var inList: Bool { KeyList.split(myListRaw).contains(item.key) }

    /// Most recently watched episode of this series, if any.
    private var lastWatched: SeriesEpisode? {
        guard let details else { return nil }
        let all = progress
        return details.episodes
            .compactMap { episode in all[episode.key].map { (episode, $0.updated) } }
            .max { $0.1 < $1.1 }?.0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DetailHeader(backdrop: details?.backdropURL, poster: item.posterURL ?? details?.posterURL,
                             title: item.title, kind: .series)
                VStack(alignment: .leading, spacing: 16) {
                    Text(item.title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                    metaLine([item.year,
                              details.map { "\($0.seasons.count) season\($0.seasons.count == 1 ? "" : "s")" },
                              details?.genre ?? item.genre,
                              (details?.rating ?? item.rating).map { "★ " + String(format: "%.1f", $0) }])
                    HStack(spacing: 10) {
                        if let next = lastWatched ?? details?.episodes.first {
                            Button { play(next) } label: {
                                primaryLabel(lastWatched != nil ? "Continue S\(next.season) · E\(next.number)"
                                                                : "Play S\(next.season) · E\(next.number)",
                                             icon: "play.fill")
                            }
                            .buttonStyle(VeyloPressStyle())
                        } else if loading {
                            primaryLabel("Loading…", icon: "hourglass").opacity(0.5)
                        }
                        Button { myListRaw = KeyList.toggled(item.key, in: myListRaw) } label: {
                            secondaryLabel("My List", icon: inList ? "checkmark" : "plus")
                        }
                        .buttonStyle(VeyloPressStyle())
                    }
                    .padding(.top, 4)
                    if let plot = details?.plot ?? item.plot {
                        Text(plot)
                            .font(.system(size: 15))
                            .foregroundStyle(VeyloTheme.textSecondary)
                            .lineLimit(6)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    episodesSection
                    InfoRow(label: "Cast", value: details?.cast)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
            }
            .padding(.bottom, 40)
        }
        .ignoresSafeArea(edges: .top)
        .background(Color.black)
        .overlay(alignment: .topTrailing) { CloseButton { dismiss() } }
        .task { await load() }
        .fullScreenCover(item: $playRequest) { request in
            VODPlayerView(request: request)
        }
    }

    @ViewBuilder private var episodesSection: some View {
        if let details, !details.episodes.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                if details.seasons.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(details.seasons, id: \.self) { number in
                                Button { withAnimation(.snappy) { season = number } } label: {
                                    Text("Season \(number)")
                                        .font(.system(size: 14, weight: season == number ? .semibold : .medium))
                                        .foregroundStyle(season == number ? Color.black : Color.white.opacity(0.75))
                                        .padding(.horizontal, 14)
                                        .frame(height: 32)
                                        .background(season == number ? Color.white : VeyloTheme.fill, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } else {
                    Text("Episodes")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(.white)
                }
                let all = progress
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(details.episodes(in: season)) { episode in
                        Button { play(episode) } label: {
                            episodeRow(episode, progress: all[episode.key]?.fraction, fallbackImage: details.backdropURL ?? item.posterURL)
                        }
                        .buttonStyle(VeyloPressStyle(scale: 0.98))
                    }
                }
            }
            .padding(.top, 8)
        } else if loading {
            ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 20)
        } else {
            VStack(spacing: 10) {
                Text(loadError == nil ? "No episodes available." : "Couldn’t load episodes.")
                    .font(.system(size: 15))
                    .foregroundStyle(VeyloTheme.textTertiary)
                Button("Try again") { Task { await load() } }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    private func episodeRow(_ episode: SeriesEpisode, progress: Double?, fallbackImage: URL?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(VeyloTheme.cardGradient)
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay { PosterImage(url: episode.imageURL ?? fallbackImage) }
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(.black.opacity(0.5), in: Circle())
                }
                .overlay(alignment: .bottom) {
                    if let progress {
                        ProgressView(value: progress).tint(.white).padding(.horizontal, 6).padding(.bottom, 5)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .frame(width: 136)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(episode.number). \(episode.title)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let duration = episode.duration {
                    Text(duration)
                        .font(.system(size: 12))
                        .foregroundStyle(VeyloTheme.textTertiary)
                }
                if let plot = episode.plot {
                    Text(plot)
                        .font(.system(size: 13))
                        .foregroundStyle(VeyloTheme.textSecondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    @MainActor private func load() async {
        loading = true
        loadError = nil
        do {
            let loaded = try await client.seriesDetails(id: item.id)
            details = loaded
            let all = progress
            let resume = loaded.episodes
                .compactMap { episode in all[episode.key].map { (episode, $0.updated) } }
                .max { $0.1 < $1.1 }?.0
            season = resume?.season ?? loaded.seasons.first ?? 1
        } catch {
            loadError = error.localizedDescription
        }
        loading = false
    }

    private func play(_ episode: SeriesEpisode) {
        guard let url = try? client.episodeURL(for: episode) else { return }
        recentSeriesRaw = KeyList.pushed(item.key, in: recentSeriesRaw)
        playRequest = VODPlayRequest(
            url: url,
            title: item.title,
            subtitle: "S\(episode.season) · E\(episode.number) · \(episode.title)",
            progressKey: episode.key,
            startAt: progress[episode.key]?.position ?? 0
        )
    }
}
