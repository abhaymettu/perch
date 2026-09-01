import SwiftUI

final class MenuBarController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private let appState = AppState()
    private var eventMonitor: Any?
    private var iconAnimator: MenuBarIconAnimator!
    private let scrollActivity = ScrollActivity()
    private var scrollMonitor: Any?
    private weak var panelContentView: NSView?
    private var panelTopLeft: NSPoint = .zero
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

        // No `sizingOptions`: `.preferredContentSize` stack-overflows on launch
        // (AppKit's resize re-enters the layout that asked for it) and
        // `.intrinsicContentSize` leaves the window stale. `syncPanelHeight`
        // pulls the size instead.
        let hostingController = NSHostingController(rootView:
            MenuBarView()
                .environment(appState)
                .environment(scrollActivity)
        )

        panel = NSPanel(
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

        startIconUpdates()

        if !hasLaunchedBefore {
            WelcomeWindowController.show()
        }
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

        syncPanelHeight()
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
    private func syncPanelHeight() {
        guard let content = panelContentView else { return }

        let height = max(content.fittingSize.height, MenuBarView.minHeight)
        guard abs(panel.frame.height - height) > 0.5 else { return }

        panel.setContentSize(NSSize(width: MenuBarView.panelWidth, height: height))
        if panelTopLeft != .zero {
            panel.setFrameTopLeftPoint(panelTopLeft)
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

    private func startIconUpdates() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.iconAnimator.setAwake(self.appState.isActive)
                self.iconAnimator.setAlert(self.appState.hasProblem)
                self.updateQuotaTitle()
                self.syncPanelHeight()
            }
        }
    }
}
