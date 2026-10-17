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
        // Soft colour pools give Liquid Glass something to refract (glass over pure black looks flat).
        ZStack(alignment: .top) {
            VeyloTheme.background
            RadialGradient(
                colors: [VeyloTheme.accent.opacity(0.26 * glow), .clear],
                center: UnitPoint(x: 0.15, y: 0),
                startRadius: 0,
                endRadius: 380
            )
            .frame(height: 560)
            RadialGradient(
                colors: [Color(red: 0.20, green: 0.45, blue: 1).opacity(0.16 * glow), .clear],
                center: UnitPoint(x: 0.95, y: 0.12),
                startRadius: 0,
                endRadius: 320
            )
            .frame(height: 560)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// The app icon (Neon Stack + Prism V), used wherever the brand appears inside the app.
struct VeyloBrandMark: View {
    var size: CGFloat = 40

    var body: some View {
        Image("BrandIcon")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: max(0.5, size / 120))
            )
            .shadow(color: VeyloTheme.accent.opacity(size > 50 ? 0.45 : 0), radius: size * 0.25, y: size * 0.08)
            .accessibilityHidden(true)
    }
}

/// "veylo" set in SF Pro Expanded Heavy with a soft white-to-lavender fill.
struct VeyloNameText: View {
    var size: CGFloat = 22

    var body: some View {
        Text("veylo")
            .font(.system(size: size, weight: .heavy).width(.expanded))
            .tracking(-size * 0.02)
            .foregroundStyle(
                LinearGradient(colors: [.white, Color(red: 0.84, green: 0.78, blue: 1)],
                               startPoint: .top, endPoint: .bottom)
            )
    }
}

struct VeyloWordmark: View {
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: size * 0.4) {
            VeyloBrandMark(size: size * 1.45)
            VeyloNameText(size: size * 0.92)
        }
    }
}

/// Full-screen splash shown while saved credentials auto-login.
struct ConnectingView: View {
    var body: some View {
        ZStack {
            VeyloBackdrop()
            VStack(spacing: 20) {
                VeyloBrandMark(size: 96)
                VeyloNameText(size: 34)
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

    /// Provider names often use superscript letters ("HINDI ᴴᴰ"); turn them into normal text.
    private static let superscripts: [Character: Character] = [
        "ᴬ": "A", "ᴮ": "B", "ᶜ": "C", "ᴰ": "D", "ᴱ": "E", "ᶠ": "F", "ᴳ": "G", "ᴴ": "H", "ᴵ": "I", "ᴶ": "J",
        "ᴷ": "K", "ᴸ": "L", "ᴹ": "M", "ᴺ": "N", "ᴼ": "O", "ᴾ": "P", "ᴿ": "R", "ˢ": "S", "ᵀ": "T", "ᵁ": "U",
        "ⱽ": "V", "ᵂ": "W", "ˣ": "X", "ʸ": "Y", "ᶻ": "Z", "ʰ": "H", "ᵈ": "D",
        "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9"
    ]

    static func normalize(_ raw: String) -> String {
        var output = ""
        var inSuperscript = false
        for character in raw {
            if let base = superscripts[character] {
                if !inSuperscript { output.append(" ") }
                output.append(base)
                inSuperscript = true
            } else {
                output.append(character)
                inSuperscript = false
            }
        }
        return output
    }

    private static let qualityPattern = #"(?i)[\(\[]?\b(4K|8K|UHD|FHD|HD|SD|HEVC|H\.?26[45]|2160P|1080P|720P|50 ?FPS|60 ?FPS)\b[\)\]]?"#

    /// Clean channel title: drops short tag prefixes ("CRIC || …") and quality marks ("HD", "(4K)").
    static func channelTitle(_ raw: String) -> String {
        var segments = normalize(raw)
            .components(separatedBy: CharacterSet(charactersIn: "|•┃│"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        while segments.count > 1, let first = segments.first, first.count <= 6 {
            segments.removeFirst()
        }
        var title = segments.joined(separator: " ")
        title = title.replacingOccurrences(of: qualityPattern, with: " ", options: .regularExpression)
        title = title.replacingOccurrences(of: #"\(\s*\)|\[\s*\]"#, with: " ", options: .regularExpression)
        let result = pretty(title)
        return result.count >= 2 ? result : pretty(raw)
    }

    static func quality(_ raw: String) -> String? {
        let words = Set(normalize(raw).uppercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        if !words.isDisjoint(with: ["4K", "8K", "UHD", "2160P"]) { return "4K" }
        if !words.isDisjoint(with: ["FHD", "1080P"]) { return "FHD" }
        if !words.isDisjoint(with: ["HD", "720P"]) { return "HD" }
        return nil
    }

    static func pretty(_ raw: String) -> String {
        var text = normalize(raw)
        for separator in ["|", "•", "┃", "│"] {
            text = text.replacingOccurrences(of: separator, with: " · ")
        }
        var tokens: [String] = []
        for token in text.split(separator: " ", omittingEmptySubsequences: true).map(String.init) {
            if token == "·" && (tokens.isEmpty || tokens.last == "·") { continue }
            tokens.append(token)
        }
        while tokens.last == "·" { tokens.removeLast() }
        text = tokens.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " .-:,"))
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
        RemoteImage(urls: [channel.logoURL].compactMap { $0 },
                    maxPixel: 360, contentMode: .fit) {
            nameplate
        }
    }

    private var nameplate: some View {
        Text(channel.title)
            .font(.system(size: nameSize, weight: .bold))
            .foregroundStyle(.white.opacity(0.88))
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.6)
    }
}

/// Neutral card with the channel logo centered, like Apple TV app tiles.
struct ChannelArtwork: View {
    let channel: PlaylistChannel
    var cornerRadius: CGFloat = 12
    var nameSize: CGFloat = 17
    var logoPadding: CGFloat = 12

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
                .overlay(alignment: .topLeading) {
                    if let quality = channel.quality {
                        Text(quality)
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .padding(7)
                    }
                }
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
