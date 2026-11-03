#if DEBUG
import SwiftUI

/// A frozen row of states. `PERCH_UI_PREVIEW=1` renders one window with each
/// scenario as a column: the menu bar item on a dark and a light bar, then the
/// popup, so a design round is one screenshot. No poll, no network.
struct PreviewScenario {
    let name: String
    var limits: [UsageLimit] = []
    var error: String?
    var stale = false
    var accounts: [AccountUsage] = []
    var menuBarAccount: String?
}

extension PreviewScenario {

    static let all: [PreviewScenario] = [accounts, mainPicked, mainSignedOut, secondStale, normal, unavailable]

    private static func resets(in hours: Double) -> Date {
        Date().addingTimeInterval(hours * 3600)
    }

    static let normal = PreviewScenario(name: "single account", limits: [
        UsageLimit(kind: "weekly_all", percent: 37, severity: "normal", resetsAt: resets(in: 70), modelName: nil),
        UsageLimit(kind: "weekly_scoped", percent: 6, severity: "normal", resetsAt: resets(in: 70), modelName: "Fable"),
    ])

    /// The 2026-11-02 shape: both accounts on Ultra, no session window, the
    /// Main account's week spent until Thursday, the Second account the default.
    private static func pair(second: AccountUsage = second, main: AccountUsage = main) -> [AccountUsage] { [second, main] }

    private static let second = AccountUsage(id: "acct2", label: "Second account", email: "second@example.com",
                                             plan: "Ultra", status: "live", reason: nil, windows: [
        UsageLimit(kind: "weekly_all", percent: 65, severity: "normal", resetsAt: resets(in: 116.5), modelName: nil),
        UsageLimit(kind: "weekly_scoped", percent: 6, severity: "normal", resetsAt: resets(in: 116.5), modelName: "Fable"),
    ], observedAt: Date().addingTimeInterval(-90))

    private static let main = AccountUsage(id: "acct1", label: "Main account", email: "you@example.com",
                                           plan: "Ultra", status: "live", reason: nil, windows: [
        UsageLimit(kind: "weekly_all", percent: 100, severity: "normal", resetsAt: resets(in: 89.4), modelName: nil),
        UsageLimit(kind: "weekly_scoped", percent: 4, severity: "normal", resetsAt: resets(in: 89.4), modelName: "Fable"),
    ], observedAt: Date().addingTimeInterval(-90))

    /// Signed out on this Mac: collapses to its header.
    private static let mainSignedOutRow = AccountUsage(id: "acct1", label: "Main account", email: "you@example.com",
                                                       plan: "Ultra", status: "removed-needs-reauth",
                                                       reason: "Signed out of this Mac; not restored", windows: [
        UsageLimit(kind: "weekly_all", percent: 99, severity: "normal", resetsAt: resets(in: 7), modelName: nil),
    ], observedAt: Date().addingTimeInterval(-55 * 60))

    static let accounts = PreviewScenario(name: "accounts", accounts: pair())

    static let mainPicked = PreviewScenario(name: "main picked", accounts: pair(), menuBarAccount: "acct1")

    static let mainSignedOut = PreviewScenario(name: "main signed out", accounts: pair(main: mainSignedOutRow),
                                               menuBarAccount: "acct2")

    /// The poller missed three polls while the Second account ran hot.
    static let secondStale = PreviewScenario(name: "second stale", accounts: pair(second: AccountUsage(
        id: "acct2", label: "Second account", email: "second@example.com", plan: "Ultra", status: "live", reason: nil, windows: [
            UsageLimit(kind: "weekly_all", percent: 84, severity: "warning", resetsAt: resets(in: 34), modelName: nil),
            UsageLimit(kind: "weekly_scoped", percent: 22, severity: "normal", resetsAt: resets(in: 34), modelName: "Fable"),
        ], observedAt: Date().addingTimeInterval(-22 * 60))))

    static let unavailable = PreviewScenario(name: "unavailable", error: "Signed out, run /login")

    var monitor: LimitsMonitor {
        LimitsMonitor(frozen: limits, error: error, stale: stale, accounts: accounts,
                      account: accounts.isEmpty ? nil : "acct2", menuBarAccount: menuBarAccount)
    }
}

// MARK: - Window

enum PreviewHarness {

    static var isEnabled: Bool { !(ProcessInfo.processInfo.environment["PERCH_UI_PREVIEW"] ?? "").isEmpty }

    private static var window: NSWindow?

    /// `PERCH_APPEARANCE=light` renders the light panel; dark otherwise.
    private static var isLight: Bool { ProcessInfo.processInfo.environment["PERCH_APPEARANCE"] == "light" }

    /// The status item as the real one draws it: the owl image, then the title in
    /// the button's 11pt medium monospaced-digit font, on a bar-coloured strip.
    private struct BarItem: View {
        let monitor: LimitsMonitor
        let dark: Bool
        var pose: OwlPose = .resting

        var body: some View {
            HStack(spacing: 3) {
                Image(nsImage: MenuBarIcon.render(pose: monitor.owlAwake ? pose : .dozing,
                                                  alert: monitor.owlAlert, isDarkMenuBar: dark))
                Text(monitor.menuBarTitle)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(dark ? Color.white : Color.black)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(dark ? Color(hex: 0x1B1B1F) : Color(hex: 0xE9E9EC))
        }
    }

    /// Every frame the animator draws (60 a second) of every move, on a dark
    /// bar. Each frame keeps its own canvas swatch, so an owl touching a
    /// swatch's edge is an owl the menu bar would clip.
    private struct Filmstrip: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(OwlMotion.everyMove, id: \.name) { name, move, alert in
                    HStack(spacing: 1) {
                        Text(name.uppercased())
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .frame(width: 58, alignment: .leading)
                        ForEach(0...Int(move.duration * 60), id: \.self) { frame in
                            let t = min(Double(frame) / 60, move.duration)
                            Image(nsImage: MenuBarIcon.render(pose: move.pose(t), alert: alert, isDarkMenuBar: true))
                                .background(Color(hex: 0x1B1B1F))
                        }
                    }
                }
            }
        }
    }

    /// Lays the scenarios out in one row, and with `PERCH_UI_SHOT` set writes
    /// that window to a PNG and quits.
    @MainActor static func present() {
        if ProcessInfo.processInfo.environment["PERCH_UI_PREVIEW"] == "hero" { return presentHero() }
        let gap: CGFloat = 26
        let scenarios = PreviewScenario.all
        let width = (UsagePopup.panelWidth + gap) * CGFloat(scenarios.count) + gap
        let height: CGFloat = ProcessInfo.processInfo.environment["PERCH_UI_PREVIEW"] == "owl" ? 800 : 420

        let content = VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: gap) {
                ForEach(scenarios, id: \.name) { scenario in
                    let monitor = scenario.monitor
                    VStack(spacing: 7) {
                        BarItem(monitor: monitor, dark: true)
                        BarItem(monitor: monitor, dark: false)
                        UsagePopup(monitor: monitor)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(scenario.name.uppercased())
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .tracking(1.4)
                            .foregroundStyle(Color.inkFaint)
                    }
                    .frame(width: UsagePopup.panelWidth, alignment: .top)
                }
            }
            if ProcessInfo.processInfo.environment["PERCH_UI_PREVIEW"] == "owl" { Filmstrip() }
        }
        .padding(gap)
        .frame(width: width, height: height, alignment: .topLeading)
        // A flat desktop tone per appearance: the panel's material is
        // translucent and over pure black every surface reads darker than it ships.
        .background(Self.isLight ? Color(hex: 0xD9DBE0) : Color(hex: 0x3A3A42))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Perch UI preview"
        window.appearance = NSAppearance(named: Self.isLight ? .aqua : .darkAqua)
        window.contentView = NSHostingView(rootView: content)
        Self.window = window
        // A shot is drawn from the window's own backing store, so it never needs
        // to be on screen: no ordering in, no activation, nothing fronted.
        if ProcessInfo.processInfo.environment["PERCH_UI_SHOT"] == nil {
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        if let path = ProcessInfo.processInfo.environment["PERCH_UI_SHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                write(window, to: path)
                NSApp.terminate(nil)
            }
        }
    }

    /// The README's picture: the popover hanging from a staged menu bar over a
    /// wallpaper, so no real account, email or number is in it.
    /// `PERCH_HERO=hot` stages a spent week on the menu bar account instead.
    @MainActor private static func presentHero() {
        let monitor = (ProcessInfo.processInfo.environment["PERCH_HERO"] == "hot"
            ? PreviewScenario.mainPicked : PreviewScenario.accounts).monitor
        let dark = !isLight
        let size = CGSize(width: 520, height: 330)
        // The real popover opens at the status item's left edge.
        let panelLeading: CGFloat = 112

        let content = ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: dark
                    ? [Color(hex: 0x14213D), Color(hex: 0x2E1F47), Color(hex: 0x0B1220)]
                    : [Color(hex: 0xB9D3F0), Color(hex: 0xE6D6F2), Color(hex: 0xF7E6D4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 16) {
                    HStack(spacing: 3) {
                        Image(nsImage: MenuBarIcon.render(pose: .resting, alert: monitor.owlAlert, isDarkMenuBar: dark))
                        Text(monitor.menuBarTitle)
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                    }
                    .padding(.horizontal, 5)
                    .frame(height: 22)
                    .background(Color.primary.opacity(0.14), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    Spacer()
                    Image(systemName: "wifi")
                    Image(systemName: "battery.75percent")
                    Text("Tue Nov 3  9:41")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.ink)
                .padding(.leading, panelLeading)
                .padding(.trailing, 16)
                .frame(height: 30)
                .background(Color.primary.opacity(0.06))

                UsagePopup(monitor: monitor)
                    .frame(width: UsagePopup.panelWidth)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: .black.opacity(dark ? 0.45 : 0.18), radius: 22, y: 12)
                    .padding(.leading, panelLeading)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)

        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = NSHostingView(rootView: content)
        Self.window = window
        if let path = ProcessInfo.processInfo.environment["PERCH_UI_SHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                write(window, to: path)
                NSApp.terminate(nil)
            }
        } else {
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Renders the window's own backing store to a PNG, which needs no Screen
    /// Recording grant. Every failure shows up as a missing file.
    private static func write(_ window: NSWindow, to path: String) {
        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }

        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?
            .write(to: URL(fileURLWithPath: path))
    }
}
#endif
