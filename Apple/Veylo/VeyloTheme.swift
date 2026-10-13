import SwiftUI

/// Shared Veylo look (Apple TV style): true black, neutral glass surfaces, white primary actions.
/// The brand violet is kept for the logo mark, focus and small accents only.
enum VeyloTheme {
    static let background = Color.black
    static let surface = Color(white: 0.11)
    static let surfaceRaised = Color(white: 0.16)
    static let fill = Color.white.opacity(0.09)
    static let stroke = Color.white.opacity(0.06)
    static let accent = Color(red: 0.62, green: 0.39, blue: 1)
    static let accentDeep = Color(red: 0.40, green: 0.22, blue: 0.88)
    static let live = Color(red: 1, green: 0.23, blue: 0.19)
    static let textSecondary = Color.white.opacity(0.6)
    static let textTertiary = Color.white.opacity(0.38)

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var cardGradient: LinearGradient {
        LinearGradient(colors: [Color(white: 0.17), Color(white: 0.09)], startPoint: .top, endPoint: .bottom)
    }
}

/// Black background with a faint brand glow at the top.
struct VeyloBackdrop: View {
    var glow: Double = 1

    var body: some View {
        ZStack(alignment: .top) {
            VeyloTheme.background
            RadialGradient(
                colors: [VeyloTheme.accent.opacity(0.20 * glow), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 420
            )
            .frame(height: 520)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct VeyloBrandMark: View {
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(VeyloTheme.accentGradient)
            Image(systemName: "play.fill")
                .font(.system(size: size * 0.40, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: size * 0.03)
        }
        .frame(width: size, height: size)
    }
}

struct VeyloWordmark: View {
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: size * 0.35) {
            VeyloBrandMark(size: size * 1.3)
            Text("veylo")
                .font(.system(size: size, weight: .bold, design: .rounded))
                .tracking(-size * 0.03)
                .foregroundStyle(.white)
        }
    }
}

/// Full-screen splash shown while saved credentials auto-login.
struct ConnectingView: View {
    var body: some View {
        ZStack {
            VeyloBackdrop()
            VStack(spacing: 20) {
                VeyloBrandMark(size: 68)
                Text("veylo")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .tracking(-1)
                    .foregroundStyle(.white)
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Signing you in…")
                        .font(.system(size: 15))
                        .foregroundStyle(VeyloTheme.textSecondary)
                }
            }
        }
    }
}

struct VeyloPressStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Display text

/// Turns provider SHOUTING CAPS into readable titles while keeping acronyms:
/// "UK: SKY SPORTS F1" → "Sky Sports F1", "PPV | LIVE EVENTS" → "PPV · Live Events",
/// "BIGG BOSS 24X7" → "Bigg Boss 24/7". Names already in mixed case are left alone.
enum VeyloText {
    private static let acronyms: Set<String> = [
        "HD", "FHD", "UHD", "SD", "HDR", "HEVC", "4K", "8K", "ESPN", "HBO", "BBC", "ITV", "CNN", "MTV", "NBA",
        "NFL", "NHL", "MLB", "UFC", "WWE", "PPV", "TNT", "DAZN", "USA", "VIP", "TV", "NBC", "ABC", "CBS", "AMC",
        "TLC", "HGTV", "CNBC", "MSNBC", "PTC", "ARY", "PTV", "BTV", "NDTV", "SAB", "EPL", "IPL", "GEC", "VOD",
        "DSTV", "RTL", "RTE", "TRT", "MBC", "OSN", "AXN", "TVB", "CBC", "CTV", "TSN", "NHK", "KBS", "SBS", "FX",
        "FXX", "TBS", "BET", "HLN", "ARD", "ZDF", "ORF", "SRF", "IPTV", "EXYU", "LATAM", "UEFA", "FIFA", "ICC"
    ]
    private static let special: [String: String] = ["BEIN": "beIN", "24X7": "24/7", "24/7": "24/7", "SYFY": "Syfy"]
    /// Two-letter words that read as words, not codes (country codes like IN/IT/NO stay upper).
    private static let smallWords: Set<String> = ["OF", "ON", "TO", "BY", "OR", "AN", "IS", "MY", "GO", "DO", "SO", "WE", "ME", "HE"]

    static func pretty(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: " | ", with: " · ").replacingOccurrences(of: "|", with: " · ")
        text = text.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        guard text.contains(where: \.isLetter), !text.contains(where: \.isLowercase) else { return text }
        return text.split(separator: " ").map { word(String($0)) }.joined(separator: " ")
    }

    private static func word(_ word: String) -> String {
        if let replacement = special[word] { return replacement }
        let core = word.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if core.isEmpty || acronyms.contains(core) || core.contains(where: \.isNumber) { return word }
        let letters = core.filter(\.isLetter)
        if letters.count <= 2 && !smallWords.contains(core) { return word }
        if !letters.contains(where: { "AEIOUY".contains($0) }) { return word }
        var result = ""
        var capitalizeNext = true
        for character in word {
            if character.isLetter {
                result += capitalizeNext ? String(character) : character.lowercased()
                capitalizeNext = false
            } else {
                result.append(character)
                if character == "-" || character == "/" { capitalizeNext = true }
            }
        }
        return result
    }
}

// MARK: - Channel artwork

/// Channel logo, or the channel name set in type when the provider has no logo.
struct ChannelLogo: View {
    let channel: PlaylistChannel
    var nameSize: CGFloat = 15

    var body: some View {
        if let logo = channel.logoURL {
            AsyncImage(url: logo, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else {
                    nameplate
                }
            }
        } else {
            nameplate
        }
    }

    private var nameplate: some View {
        Text(channel.title)
            .font(.system(size: nameSize, weight: .semibold))
            .foregroundStyle(.white.opacity(0.78))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
    }
}

/// Neutral card with the channel logo centered, like Apple TV app tiles.
struct ChannelArtwork: View {
    let channel: PlaylistChannel
    var cornerRadius: CGFloat = 12
    var nameSize: CGFloat = 15
    var logoPadding: CGFloat = 18

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape.fill(VeyloTheme.cardGradient)
            ChannelLogo(channel: channel, nameSize: nameSize)
                .padding(logoPadding)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(VeyloTheme.stroke, lineWidth: 1))
    }
}

struct ChannelTile: View {
    let channel: PlaylistChannel
    /// Second line under the name (category and/or country flag). Hidden when nil.
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ChannelArtwork(channel: channel)
                .aspectRatio(16 / 9, contentMode: .fit)
                .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(VeyloTheme.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
    }
}
