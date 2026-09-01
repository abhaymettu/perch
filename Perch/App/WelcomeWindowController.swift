import SwiftUI

enum WelcomeWindowController {
    private static var window: NSWindow?

    @MainActor
    static func show() {
        guard window == nil else { return }

        let hostingView = NSHostingView(rootView: WelcomeView())
        hostingView.frame = NSRect(origin: .zero, size: WelcomeView.size)

        let w = NSWindow(
            contentRect: NSRect(origin: .zero, size: WelcomeView.size),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.contentView = hostingView
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.center()
        w.isReleasedWhenClosed = false
        w.makeKeyAndOrderFront(nil)

        window = w
    }

    @MainActor
    static func close() {
        window?.close()
        window = nil
    }
}
