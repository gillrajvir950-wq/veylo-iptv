import SwiftUI

/// Liquid Glass (iOS 26) with a frosted-material fallback for older iOS versions.
/// Built only when the build machine has the iOS 26 SDK (Swift 6.2+); otherwise the fallback is used.
extension View {
    /// Glass surface in `shape`. `interactive` makes it react to touches (buttons, bars).
    @ViewBuilder
    func veyloGlass<S: InsettableShape>(in shape: S, interactive: Bool = false, tint: Color? = nil) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            self.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            self.modifier(FrostedGlass(shape: shape, tint: tint))
        }
        #else
        self.modifier(FrostedGlass(shape: shape, tint: tint))
        #endif
    }

    /// Capsule-shaped glass, the most common case.
    func veyloGlassCapsule(interactive: Bool = false, tint: Color? = nil) -> some View {
        veyloGlass(in: Capsule(), interactive: interactive, tint: tint)
    }

    /// Circular glass for round icon buttons.
    func veyloGlassCircle(interactive: Bool = true, tint: Color? = nil) -> some View {
        veyloGlass(in: Circle(), interactive: interactive, tint: tint)
    }
}

/// Pre-iOS 26 look: blur + soft edge highlight.
private struct FrostedGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(tint?.opacity(0.35) ?? Color.black.opacity(0.25))
                }
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.06)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.8)
            }
            .environment(\.colorScheme, .dark)
    }
}

/// Groups nearby glass shapes so they blend and morph together on iOS 26.
struct VeyloGlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder let content: () -> Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
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
