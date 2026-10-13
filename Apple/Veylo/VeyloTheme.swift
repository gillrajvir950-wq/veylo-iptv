import SwiftUI

/// Shared Veylo look: colors, backdrop, brand mark and channel artwork.
enum VeyloTheme {
    static let background = Color(red: 0.035, green: 0.039, blue: 0.063)
    static let surface = Color(red: 0.078, green: 0.086, blue: 0.125)
    static let surfaceRaised = Color(red: 0.118, green: 0.129, blue: 0.180)
    static let stroke = Color.white.opacity(0.07)
    static let accent = Color(red: 0.62, green: 0.39, blue: 1)
    static let accentDeep = Color(red: 0.40, green: 0.22, blue: 0.88)
    static let live = Color(red: 1, green: 0.25, blue: 0.32)
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.38)

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Dark background with a soft brand glow.
struct VeyloBackdrop: View {
    var body: some View {
        ZStack {
            VeyloTheme.background
            Circle()
                .fill(VeyloTheme.accent.opacity(0.30))
                .frame(width: 440, height: 440)
                .blur(radius: 130)
                .offset(x: -150, y: -330)
            Circle()
                .fill(Color(red: 0.20, green: 0.45, blue: 1).opacity(0.16))
                .frame(width: 380, height: 380)
                .blur(radius: 130)
                .offset(x: 170, y: -200)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct VeyloBrandMark: View {
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(VeyloTheme.accentGradient)
            Image(systemName: "play.fill")
                .font(.system(size: size * 0.40, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: size * 0.03)
        }
        .frame(width: size, height: size)
        .shadow(color: VeyloTheme.accent.opacity(0.45), radius: size * 0.3, y: size * 0.1)
    }
}

struct VeyloWordmark: View {
    var size: CGFloat = 24

    var body: some View {
        HStack(spacing: size * 0.4) {
            VeyloBrandMark(size: size * 1.4)
            Text("veylo")
                .font(.system(size: size, weight: .black, design: .rounded))
                .tracking(-size * 0.04)
                .foregroundStyle(.white)
        }
    }
}

/// Full-screen splash shown while saved credentials auto-login.
struct ConnectingView: View {
    var body: some View {
        ZStack {
            VeyloBackdrop()
            VStack(spacing: 22) {
                VeyloBrandMark(size: 72)
                Text("veylo")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .tracking(-1.5)
                    .foregroundStyle(.white)
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Signing you in…")
                        .font(.system(size: 15, weight: .medium))
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
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Channel logo on a tinted card, with initials when the provider has no logo.
struct ChannelArtwork: View {
    let channel: PlaylistChannel
    var cornerRadius: CGFloat = 14
    var monogramSize: CGFloat = 24
    var logoPadding: CGFloat = 16

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(
                colors: [tint.opacity(0.42), VeyloTheme.surfaceRaised],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            if let logo = channel.logoURL {
                AsyncImage(url: logo) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit().padding(logoPadding)
                    } else {
                        monogram
                    }
                }
            } else {
                monogram
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(VeyloTheme.stroke, lineWidth: 1))
    }

    private var monogram: some View {
        Text(Self.initials(for: channel.title))
            .font(.system(size: monogramSize, weight: .heavy, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(6)
    }

    /// Stable per-channel hue (String.hashValue changes every launch, so use djb2).
    private var tint: Color {
        var hash: UInt32 = 5381
        for scalar in channel.title.unicodeScalars { hash = (hash &* 33) &+ scalar.value }
        return Color(hue: Double(hash % 360) / 360, saturation: 0.6, brightness: 0.8)
    }

    /// "UK: BBC One HD" -> "BO", "|IN| Star Gold" -> "SG", "Sky" -> "SK".
    static func initials(for name: String) -> String {
        var core = Substring(name)
        for _ in 0..<3 {
            guard let separator = core.firstIndex(where: { $0 == ":" || $0 == "|" }),
                  core.distance(from: core.startIndex, to: separator) <= 5 else { break }
            core = core[core.index(after: separator)...]
        }
        var words = core.split { !$0.isLetter && !$0.isNumber }
        if words.isEmpty { words = Substring(name).split { !$0.isLetter && !$0.isNumber } }
        guard let first = words.first else { return "TV" }
        if words.count == 1 { return String(first.prefix(2)).uppercased() }
        return words.prefix(2).compactMap(\.first).map { String($0).uppercased() }.joined()
    }
}

struct ChannelTile: View {
    let channel: PlaylistChannel
    var showsCategory = true
    /// Country flag shown on the artwork ("🇬🇧"), when known.
    var flag: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ChannelArtwork(channel: channel)
                .aspectRatio(16 / 10, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    if let flag {
                        Text(flag)
                            .font(.system(size: 13))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.45), in: Capsule())
                            .padding(7)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if showsCategory {
                    Text(channel.category)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(VeyloTheme.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
    }
}
