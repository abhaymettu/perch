import SwiftUI

extension Notification.Name {
    /// Panel is being shown. The view resets to a closed, main-page state.
    static let perchPanelWillOpen = Notification.Name("perch.panel.willOpen")
    /// The view changed height on its own (a section opened). AppKit owns the
    /// window frame, so it has to be told rather than poll for it.
    static let perchPanelLayoutChanged = Notification.Name("perch.panel.layoutChanged")
    /// A row wants the panel gone before it does something that steals focus
    /// (activating another app), so the panel doesn't sit open behind it.
    static let perchPanelShouldClose = Notification.Name("perch.panel.shouldClose")
    /// Panel is going away. Anything looping for the viewer's benefit stops.
    static let perchPanelDidClose = Notification.Name("perch.panel.didClose")
}

/// Without `.titled`, AppKit's default `canBecomeKey` is false, so
/// `makeKeyAndOrderFront` silently never makes this the key window (verified
/// via Accessibility: `AXMain`/`focused` both read false on the open panel).
/// A click still hit-tests to the right AXButton, but with no key window the
/// event never reaches the tap gesture underneath. Overriding this is what
/// lets a single click register.
final class ClickThroughPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class MenuBarController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private lazy var panel: NSPanel = makePanel()
    private let appState = AppState()
    private var eventMonitor: Any?
    private var iconAnimator: MenuBarIconAnimator!
    private let scrollActivity = ScrollActivity()
    private var scrollMonitor: Any?
    private weak var panelContentView: NSView?
    private var panelTopLeft: NSPoint = .zero
    // `NSHostingController.sizingOptions = []` (below) means AppKit no longer
    // tracks `panelContentView.fittingSize` — it reads back 0 always. SwiftUI
    // measures its own content instead and reports it here via
    // `.perchPanelLayoutChanged`'s userInfo.
    private var lastReportedHeight: CGFloat = MenuBarView.minHeight
    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The panel floats over an uncontrolled wallpaper: a light appearance
        // drops its labels to near-black and they vanish into the material.
        NSApp.appearance = NSAppearance(named: .darkAqua)

        #if DEBUG
        ClaudeScanner.selfCheck()
        LimitsMonitor.selfCheck()
        LaunchAgent.selfCheck()
        FailureBox.selfCheck()
        Task { await Shell.selfCheck() }

        if PreviewHarness.isEnabled {
            NSApp.setActivationPolicy(.regular)
            PreviewHarness.present()
            return
        }
        #endif

        // Variable length: the quota time sits beside the owl as the
        // button's title, which a square item would clip.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.action = #selector(togglePanel)
            button.target = self
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        }

        iconAnimator = MenuBarIconAnimator(button: statusItem.button)

        // Next runloop pass, not this one: the notification is posted from
        // inside the SwiftUI action, before the layout it is about has run.
        NotificationCenter.default.addObserver(
            forName: .perchPanelLayoutChanged, object: nil, queue: .main
        ) { [weak self] notification in
            if let height = notification.userInfo?["height"] as? CGFloat {
                self?.lastReportedHeight = height
            }
            DispatchQueue.main.async {
                self?.syncPanelHeight()
            }
        }

        // Next runloop pass, not this one: the notification is posted from
        // inside the SwiftUI tap handler that is still on the call stack.
        NotificationCenter.default.addObserver(
            forName: .perchPanelShouldClose, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.hardClosePanel()
            }
        }

        startIconUpdates()

        if !hasLaunchedBefore {
            WelcomeWindowController.show()
        }
    }

    /// Built on the first click, not at launch: until someone opens it, the
    /// SwiftUI panel is memory and an offscreen re-layout on every state
    /// change, for a window nobody has seen.
    private func makePanel() -> NSPanel {
        // No `sizingOptions`: `.preferredContentSize` stack-overflows on launch
        // (AppKit's resize re-enters the layout that asked for it) and
        // `.intrinsicContentSize` leaves the window stale. `syncPanelHeight`
        // pulls the size instead.
        let hostingController = NSHostingController(rootView:
            MenuBarView()
                .environment(appState)
                .environment(scrollActivity)
        )
        // Empty, not the AppKit default: with any sizing option set,
        // NSHostingView recomputes the window's content-size extrema on every
        // constraints pass, and a state change from a plain tap (no resize
        // code involved) can trigger that recompute *during* an in-flight
        // updateConstraints pass — AppKit throws over the reentrant
        // setNeedsUpdateConstraints: call (verified via crash log). This
        // panel's height is fully owned by syncPanelHeight() already.
        hostingController.sizingOptions = []

        let panel = ClickThroughPanel(
            contentRect: NSRect(origin: .zero, size: MenuBarView.panelSize),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panelContentView = hostingController.view
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovable = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false

        // One layout pass now, so the view has reported its height before the
        // first open sizes the panel; otherwise that open grows from minHeight.
        hostingController.view.layoutSubtreeIfNeeded()
        return panel
    }

    @objc private func togglePanel() {
        if panel.isVisible {
            closePanel()
        } else {
            openPanel()
        }
    }

    private func openPanel() {
        guard let button = statusItem.button,
              let buttonWindow = button.window else { return }

        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        var x = buttonFrame.minX
        if let screen = buttonWindow.screen {
            x = min(x, screen.visibleFrame.maxX - MenuBarView.panelWidth - 8)
        }
        panelTopLeft = NSPoint(x: x, y: buttonFrame.minY - 4)

        // Sizes to whatever height was last reported; the reset this posts
        // (closed sections, main page) lands its own corrected height
        // asynchronously through .perchPanelLayoutChanged, same as any other
        // in-panel layout change.
        NotificationCenter.default.post(name: .perchPanelWillOpen, object: nil)
        appState.isPanelOpen = true

        syncPanelHeight(animated: false)
        panel.setFrameTopLeftPoint(panelTopLeft)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }

        growFromMenuBar()

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanel()
        }

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            Task { @MainActor in self?.scrollActivity.noteScroll() }
            return event
        }
    }

    private func growFromMenuBar() {
        guard let layer = panelContentView?.layer else { return }

        let frame = layer.frame
        layer.anchorPoint = CGPoint(x: 0.5, y: 1)
        layer.frame = frame

        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue = 0.92
        spring.toValue = 1
        spring.mass = 1
        spring.stiffness = 260
        spring.damping = 20
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "pop")
    }

    private func closePanel() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.panel.alphaValue == 0 else { return }
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
        })

        removeMonitors()
    }

    /// No fade: the caller is about to steal focus by activating another
    /// app, so the panel should just be gone rather than mid-animation.
    private func hardClosePanel() {
        removeMonitors()
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    private func removeMonitors() {
        appState.isPanelOpen = false
        NotificationCenter.default.post(name: .perchPanelDidClose, object: nil)

        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
    }

    /// The panel is as tall as what is running. AppKit resizes a window about
    /// its bottom-left corner and the panel hangs from the menu bar, so the top
    /// is re-pinned after every resize. The `!=` guard makes this idempotent —
    /// that is what stops it becoming the feedback loop `.preferredContentSize`
    /// was.
    private func syncPanelHeight(animated: Bool = true) {
        let height = max(lastReportedHeight, MenuBarView.minHeight)
        guard abs(panel.frame.height - height) > 0.5 else { return }

        // One animated setFrame, not setContentSize plus a re-pin: two separate
        // frame writes are what made the resize land as a jump and a shove.
        // maxY is held so the growth goes downward, away from the menu bar.
        var frame = panel.frame
        frame.size = NSSize(width: MenuBarView.panelWidth, height: height)
        frame.origin.y = panel.frame.maxY - height

        guard animated else { return panel.setFrame(frame, display: true) }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    @MainActor
    private func updateQuotaTitle() {
        // Empty string, not nil: AppKit keeps the old title otherwise.
        let title = appState.usage.menuBarTitle
        if statusItem.button?.title != title {
            statusItem.button?.title = title
        }
    }

    /// The owl and the quota title follow state as it changes rather than
    /// checking it every second. Time alone moves only the reset countdown (in
    /// whole minutes) and a session's slide into stale (hours), so those get a
    /// slow tick. Panel height is owned by `.perchPanelLayoutChanged`.
    private func startIconUpdates() {
        MainActor.assumeIsolated { observeIconState() }

        let tick = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateIcon() }
        }
        tick.tolerance = 10
        RunLoop.main.add(tick, forMode: .common)
    }

    @MainActor
    private func observeIconState() {
        withObservationTracking {
            updateIcon()
        } onChange: { [weak self] in
            DispatchQueue.main.async { self?.observeIconState() }
        }
    }

    @MainActor
    private func updateIcon() {
        iconAnimator.setAwake(appState.isActive)
        iconAnimator.setAlert(appState.hasProblem)
        updateQuotaTitle()
    }
}
