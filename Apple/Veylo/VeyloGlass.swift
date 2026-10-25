import SwiftUI

/// Liquid Glass (iOS 26) with a frosted-material fallback for older iOS versions.
/// Built only when the build machine has the iOS 26 SDK (Swift 6.2+); otherwise the fallback is used.
extension View {
    /// Glass surface in `shape`, drawn as a separate layer *behind* the content.
    /// The glass layer never takes touches (iOS 26 glass inside button labels was swallowing taps),
    /// and the whole shape counts as the tap area of the view it decorates.
    /// `interactive` is kept for call-site compatibility but no longer used.
    /// `liquid`: real iOS 26 Liquid Glass. Only for large surfaces (tab bar, search fields, cards) —
    /// on small buttons/chips iOS 26 drew the glass over the icon/title (empty circles, blank chips, 0.0.44).
    /// Everything else uses the frosted look, which always stays behind the content.
    func veyloGlass<S: InsettableShape>(in shape: S, interactive: Bool = false, tint: Color? = nil, liquid: Bool = false) -> some View {
        self
            .background {
                GlassBackdrop(shape: shape, tint: tint, liquid: liquid)
                    .allowsHitTesting(false)
            }
            .contentShape(shape)
    }

    /// Capsule-shaped glass, the most common case.
    func veyloGlassCapsule(interactive: Bool = false, tint: Color? = nil, liquid: Bool = false) -> some View {
        veyloGlass(in: Capsule(), interactive: interactive, tint: tint, liquid: liquid)
    }

    /// Circular glass for round icon buttons.
    func veyloGlassCircle(interactive: Bool = false, tint: Color? = nil) -> some View {
        veyloGlass(in: Circle(), interactive: interactive, tint: tint)
    }
}

/// The glass itself: Liquid Glass on iOS/macOS 26, a frosted blur before that.
private struct GlassBackdrop<S: InsettableShape>: View {
    let shape: S
    let tint: Color?
    let liquid: Bool

    var body: some View {
        #if compiler(>=6.2)
        if liquid, #available(iOS 26.0, macOS 26.0, *) {
            Color.clear.glassEffect(Glass.regular.tint(tint), in: shape)
        } else {
            frosted
        }
        #else
        frosted
        #endif
    }

    private var frosted: some View {
        ZStack {
            shape.fill(.ultraThinMaterial)
            shape.fill(tint?.opacity(0.35) ?? Color.black.opacity(0.25))
            shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.06)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 0.8)
        }
        .environment(\.colorScheme, .dark)
    }
}

/// Layout wrapper kept for call sites. It no longer uses GlassEffectContainer: the container
/// composites all glass in one layer, which painted over the labels (chip titles disappeared).
struct VeyloGlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder let content: () -> Content

    var body: some View { content() }
}

/// Round glass icon button used by the players and detail screens.
struct GlassIconButton: View {
    let systemName: String
    var size: CGFloat = 44
    var iconSize: CGFloat = 17
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(VeyloPressStyle(scale: 0.92))
        .veyloGlassCircle(tint: tint)
    }
}
