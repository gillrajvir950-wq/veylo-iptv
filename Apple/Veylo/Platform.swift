import SwiftUI
#if os(iOS)
import UIKit
#endif

// Small cross-platform layer so the same Veylo screens build for iPhone/iPad (iOS) and Mac (macOS).
// On iOS every helper below calls exactly the modifier the app used before, so iPhone behaviour
// is unchanged. On macOS the iOS-only parts become no-ops or Mac equivalents.

#if os(macOS)
import AppKit

/// The image pipeline is written against UIImage; on the Mac it is NSImage.
typealias UIImage = NSImage

extension NSImage {
    convenience init(cgImage: CGImage) {
        self.init(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// Pixel scale used for cache cost (NSImage sizes are already in points).
    var scale: CGFloat { 1 }

    var cgImage: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    func jpegData(compressionQuality: CGFloat) -> Data? {
        guard let cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cgImage)
            .representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }

    func pngData() -> Data? {
        guard let cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }
}

extension Image {
    init(uiImage: NSImage) { self.init(nsImage: uiImage) }
}
#endif

#if os(iOS)
typealias VeyloNativeView = UIView
#else
typealias VeyloNativeView = NSView

/// Black video host for VLC on the Mac. Mouse clicks pass through to the SwiftUI controls above
/// (same idea as `isUserInteractionEnabled = false` on iPhone).
final class PassThroughVideoView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
#endif

enum VeyloPlatform {
    #if os(macOS)
    static let isMac = true
    #else
    static let isMac = false
    #endif

    #if os(macOS)
    /// The app's main window (not the player sheet).
    static var mainWindow: NSWindow? {
        let candidates = NSApp.windows.filter { $0.sheetParent == nil && $0.isVisible }
        return NSApp.mainWindow.flatMap { $0.sheetParent ?? $0 } ?? candidates.first
    }

    static var mainWindowSize: CGSize {
        guard let window = mainWindow else { return CGSize(width: 1280, height: 800) }
        let size = window.contentLayoutRect.size
        return CGSize(width: max(size.width, 600), height: max(size.height, 400))
    }

    static var isWindowFullScreen: Bool {
        mainWindow?.styleMask.contains(.fullScreen) ?? false
    }

    /// Real macOS full screen for the app window (the player sheet grows with it).
    static func setWindowFullScreen(_ on: Bool) {
        guard let window = mainWindow, window.styleMask.contains(.fullScreen) != on else { return }
        window.toggleFullScreen(nil)
    }
    #endif

    /// Keeps the screen awake while a movie plays (iOS only; the Mac handles this itself).
    static func setIdleTimerDisabled(_ disabled: Bool) {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    }
}

extension View {
    /// URL keyboard on iPhone.
    @ViewBuilder func urlKeyboard() -> some View {
        #if os(iOS)
        self.keyboardType(.URL)
        #else
        self
        #endif
    }

    /// No automatic capitals (URLs, usernames).
    @ViewBuilder func noAutocapitalization() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never)
        #else
        self
        #endif
    }

    @ViewBuilder func largeNavigationTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.large)
        #else
        self
        #endif
    }

    @ViewBuilder func inlineNavigationTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder func veyloStatusBarHidden(_ hidden: Bool = true) -> some View {
        #if os(iOS)
        self.statusBarHidden(hidden)
        #else
        self
        #endif
    }

    @ViewBuilder func hideTabBar() -> some View {
        #if os(iOS)
        self.toolbar(.hidden, for: .tabBar)
        #else
        self
        #endif
    }

    @ViewBuilder func hideNavigationBar() -> some View {
        #if os(iOS)
        self.toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }

    /// "Done" above the iPhone keyboard.
    @ViewBuilder func keyboardDoneButton(_ action: @escaping () -> Void) -> some View {
        #if os(iOS)
        self.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done", action: action)
            }
        }
        #else
        self
        #endif
    }

    /// Full-screen player on iPhone; a large window-sized sheet on the Mac.
    @ViewBuilder func veyloFullScreenCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(iOS)
        self.fullScreenCover(item: item, content: content)
        #else
        self.modifier(MacPlayerSheet(item: item, sheetContent: content))
        #endif
    }
}

/// Closes a player shown in its own Mac window (nil on iPhone, where the system dismiss is used).
private struct VeyloCloseKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var veyloClose: (() -> Void)? {
        get { self[VeyloCloseKey.self] }
        set { self[VeyloCloseKey.self] = newValue }
    }
}

#if os(macOS)
/// Mac: the player opens in its own black window (sized like the app window). Sheets could not
/// cover the whole screen — the movie player even opened as a sheet inside the detail sheet.
private struct MacPlayerSheet<Item: Identifiable, SheetContent: View>: ViewModifier {
    @Binding var item: Item?
    let sheetContent: (Item) -> SheetContent

    func body(content: Content) -> some View {
        content
            .onChange(of: item?.id) { _, id in
                if id == nil {
                    MacPlayerWindow.shared.close(notify: false)
                } else if let value = item {
                    MacPlayerWindow.shared.show(sheetContent(value)) { item = nil }
                }
            }
    }
}

/// The single player window on the Mac.
final class MacPlayerWindow: NSObject, NSWindowDelegate {
    static let shared = MacPlayerWindow()
    private var window: NSWindow?
    private var onClose: (() -> Void)?

    func show<V: View>(_ view: V, onClose: @escaping () -> Void) {
        close(notify: true)
        let frame = VeyloPlatform.mainWindow?.frame ?? NSRect(x: 120, y: 120, width: 1280, height: 800)
        let root = view
            .environment(\.veyloClose, { [weak self] in self?.close(notify: true) })
            .frame(minWidth: 640, minHeight: 360)
            .background(Color.black)
            .preferredColorScheme(.dark)
        let host = NSHostingController(rootView: AnyView(root))
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .black
        window.collectionBehavior = [.fullScreenPrimary]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.title = "Veylo Player"
        window.setFrame(frame, display: true)
        self.window = window
        self.onClose = onClose
        window.makeKeyAndOrderFront(nil)
    }

    /// `notify` tells the opener (so its `item` goes back to nil).
    func close(notify: Bool) {
        guard let window else { return }
        let callback = notify ? onClose : nil
        self.window = nil
        onClose = nil
        window.delegate = nil
        window.close()
        callback?()
    }

    func windowWillClose(_ notification: Notification) {
        // Red close button or ⌘W.
        guard (notification.object as? NSWindow) === window else { return }
        let callback = onClose
        window = nil
        onClose = nil
        callback?()
    }
}
#endif

/// Swipeable featured carousel: paged TabView on iPhone, snapping horizontal scroll on the Mac.
struct VeyloPager<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    let items: Data
    @ViewBuilder let content: (Data.Element) -> Content

    var body: some View {
        #if os(iOS)
        TabView {
            ForEach(items) { item in content(item) }
        }
        .tabViewStyle(.page(indexDisplayMode: items.count > 1 ? .always : .never))
        #else
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(items) { item in
                        content(item)
                            .frame(width: min(geometry.size.width, 760))
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
        }
        #endif
    }
}
