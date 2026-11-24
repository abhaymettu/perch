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
    /// Another account was picked for the menu bar.
    static let perchMenuBarAccountChanged = Notification.Name("perch.menuBarAccount.changed")
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
    private var panel: NSPanel!
    private let usage = LimitsMonitor()
    private let noSleep = NoSleep()
    private let targets = MessageTargets()
    /// A send's result showing in the bar instead of the number, until then.
    private var flashUntil: Date?
    /// What the button last drew, so an unchanged second costs a compare.
    private var shownTitle: String?
    private var shownNoSleep = false
    private var eventMonitor: Any?
    private var owl: OwlDirector!
    /// The number the owl last saw, so it can tell when it moves.
    private var lastReading: MenuBarReading?
    /// The title waits while the owl turns its back on an account switch.
    private var titleIsHeld = false
    private weak var panelContentView: NSView?
    private var panelTopLeft: NSPoint = .zero
    // `NSHostingController.sizingOptions = []` (below) means AppKit no longer
    // tracks `panelContentView.fittingSize`, it reads back 0 always. SwiftUI
    // measures its own content instead and reports it here via
    // `.perchPanelLayoutChanged`'s userInfo.
    private var lastReportedHeight: CGFloat = UsagePopup.minHeight

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        LimitsMonitor.selfCheck()
        MenuBarIcon.selfCheck()
        Task { await Shell.selfCheck() }
        Task { await NoSleep.selfCheck() }
        MessageTargets.selfCheck() // about 0.6 s, before the harness can write a PNG

        if PreviewHarness.isEnabled {
            // A shot never shows a Dock icon or a window; see PreviewHarness.
            if ProcessInfo.processInfo.environment["PERCH_UI_SHOT"] == nil { NSApp.setActivationPolicy(.regular) }
            PreviewHarness.present()
            return
        }
        #endif

        // Variable length: the owl plus the "44%" title.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.action = #selector(togglePanel)
            button.target = self
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        }

        owl = OwlDirector(button: statusItem.button)

        // No `sizingOptions`: `.preferredContentSize` stack-overflows on launch
        // (AppKit's resize re-enters the layout that asked for it) and
        // `.intrinsicContentSize` leaves the window stale. `syncPanelHeight`
        // pulls the size instead.
        let hostingController = NSHostingController(rootView:
            UsagePopup(monitor: usage, noSleep: noSleep, targets: targets)
        )
        // Empty, not the AppKit default: with any sizing option set,
        // NSHostingView recomputes the window's content-size extrema on every
        // constraints pass, and a state change from a plain tap (no resize
        // code involved) can trigger that recompute *during* an in-flight
        // updateConstraints pass, AppKit throws over the reentrant
        // setNeedsUpdateConstraints: call (verified via crash log). This
        // panel's height is fully owned by syncPanelHeight() already.
        hostingController.sizingOptions = []

        panel = ClickThroughPanel(
            contentRect: NSRect(origin: .zero, size: CGSize(width: UsagePopup.panelWidth, height: UsagePopup.minHeight)),
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

        // Picking an account sends the owl all the way round; its number lands
        // in the menu bar while the back of its head is showing.
        NotificationCenter.default.addObserver(
            forName: .perchMenuBarAccountChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.titleIsHeld = true
                self.owl.switchAccount { [weak self] in
                    self?.titleIsHeld = false
                    self?.updateQuotaTitle()
                }
            }
        }

        // `Perch send` runs as its own process and reports here; so does a
        // `Perch target` from a terminal, which the switch has to follow.
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(forName: MessageTargets.messageSent, object: nil, queue: .main) { [weak self] note in
            let info = note.userInfo as? [String: String] ?? [:]
            guard let name = info["target"] else { return }
            let result = SendResult(target: name, ok: info["ok"] == "1", detail: info["detail"] ?? "", at: Date())
            MainActor.assumeIsolated { self?.showSent(result) }
        }
        distributed.addObserver(forName: MessageTargets.targetChanged, object: nil, queue: .main) { [weak self] _ in
            self?.targets.reload()
        }

        MainActor.assumeIsolated { startTitleUpdates() }
    }

    /// The bar says how a send went, in words with a mark beside them (a tick,
    /// or a warning triangle), so it never rests on colour. Two and a half
    /// seconds for a send that went, eight for one that did not.
    @MainActor
    private func showSent(_ result: SendResult) {
        targets.record(result)
        guard let button = statusItem.button else { return }
        let font = button.font ?? .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let symbol = result.ok ? "checkmark" : "exclamationmark.triangle.fill"
        let text = NSMutableAttributedString()
        if let mark = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 9.5, weight: .bold)) {
            mark.isTemplate = true
            let attachment = NSTextAttachment()
            attachment.image = mark
            attachment.bounds = CGRect(x: 0, y: ((font.capHeight - mark.size.height) / 2).rounded(),
                                       width: mark.size.width, height: mark.size.height)
            text.append(NSAttributedString(attachment: attachment))
            text.append(NSAttributedString(string: " ", attributes: [.font: font]))
        }
        text.append(NSAttributedString(string: result.headline, attributes: [.font: font]))
        button.attributedTitle = text
        button.toolTip = result.ok ? result.headline : "\(result.headline): \(result.detail)"
        shownTitle = nil
        let until = Date().addingTimeInterval(result.ok ? 2.5 : 8)
        flashUntil = until
        DispatchQueue.main.asyncAfter(deadline: .now() + until.timeIntervalSinceNow) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.flashUntil == until else { return }
                self.flashUntil = nil
                self.updateQuotaTitle()
            }
        }
    }

    @objc private func togglePanel() {
        MainActor.assumeIsolated { owl.pressed() }
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
            x = min(x, screen.visibleFrame.maxX - UsagePopup.panelWidth - 8)
        }
        panelTopLeft = NSPoint(x: x, y: buttonFrame.minY - 4)

        // Sizes to whatever height was last reported; the reset this posts
        // (closed sections, main page) lands its own corrected height
        // asynchronously through .perchPanelLayoutChanged, same as any other
        // in-panel layout change.
        NotificationCenter.default.post(name: .perchPanelWillOpen, object: nil)

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
        MainActor.assumeIsolated { owl.setAttending(true) }

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanel()
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
        MainActor.assumeIsolated { owl.setAttending(false) }
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    /// The panel is as tall as what is running. AppKit resizes a window about
    /// its bottom-left corner and the panel hangs from the menu bar, so the top
    /// is re-pinned after every resize. The `!=` guard makes this idempotent -
    /// that is what stops it becoming the feedback loop `.preferredContentSize`
    /// was.
    private func syncPanelHeight(animated: Bool = true) {
        let height = max(lastReportedHeight, UsagePopup.minHeight)
        guard abs(panel.frame.height - height) > 0.5 else { return }

        // One animated setFrame, not setContentSize plus a re-pin: two separate
        // frame writes are what made the resize land as a jump and a shove.
        // maxY is held so the growth goes downward, away from the menu bar.
        var frame = panel.frame
        frame.size = NSSize(width: UsagePopup.panelWidth, height: height)
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
        guard !titleIsHeld, flashUntil == nil else { return }
        let title = usage.menuBarTitle
        let noSleepOn = noSleep.isOn == true
        if title != shownTitle || noSleepOn != shownNoSleep, let button = statusItem.button {
            shownTitle = title
            shownNoSleep = noSleepOn
            if noSleepOn {
                button.attributedTitle = Self.titleWithCup(title, font: button.font)
                button.toolTip = "No Sleep is on: the Mac stays awake with the lid closed"
            } else {
                button.title = title
                button.toolTip = nil
            }
        }

        // The owl looks at the number when it moves. A reading that vanishes
        // (stale, signed out) keeps the last one, so the week rolling over is
        // still seen as a smaller number arriving.
        guard let reading = usage.menuBarReading() else { return }
        if let lastReading { owl.readingChanged(from: lastReading, to: reading) }
        lastReading = reading
    }

    /// No Sleep's mark in the bar: a full cup after the number, the same cup
    /// the panel's switch shows. A shape, so it reads without colour. A
    /// template image, so the bar tints it like the text beside it.
    private static func titleWithCup(_ title: String, font: NSFont?) -> NSAttributedString {
        let font = font ?? .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let text = NSMutableAttributedString(string: title.isEmpty ? "" : title + " ", attributes: [.font: font])
        let cup = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: "No Sleep is on")?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
        guard let cup else { return text }
        cup.isTemplate = true
        let attachment = NSTextAttachment()
        attachment.image = cup
        // Centred on the digits' cap height, not sat on the baseline.
        attachment.bounds = CGRect(x: 0, y: ((font.capHeight - cup.size.height) / 2).rounded(),
                                   width: cup.size.width, height: cup.size.height)
        text.append(NSAttributedString(attachment: attachment))
        return text
    }

    /// The title only changes when a fetch lands or state.json is rewritten,
    /// so this is a stat, a registry read and a cheap string compare once a second. The owl is awake while usage is
    /// readable and amber when a window is critical or the fetch is failing;
    /// both setters ignore an unchanged value.
    @MainActor
    private func startTitleUpdates() {
        updateQuotaTitle()
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Title and cards both follow state.json; it is re-read the second the poller writes it.
                self.usage.reloadAccountsIfChanged()
                // Followed, never assumed: a pmset from a terminal shows here within the second.
                self.noSleep.refresh()
                self.owl.setAwake(self.usage.owlAwake)
                self.owl.setAlert(self.usage.owlAlert)
                self.updateQuotaTitle()
                self.syncPanelHeight()
            }
        }
    }
}
