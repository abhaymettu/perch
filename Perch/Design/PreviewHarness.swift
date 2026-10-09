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

    static let all: [PreviewScenario] = [accounts, mainPicked, secondStale, normal, hot, stale, unavailable]

    private static func resets(in hours: Double) -> Date {
        Date().addingTimeInterval(hours * 3600)
    }

    /// The numbers the live endpoint returned on 2026-10-06 19:30 CDT.
    static let normal = PreviewScenario(name: "normal", limits: [
        UsageLimit(kind: "session", percent: 13, severity: "normal", resetsAt: resets(in: 2.0), modelName: nil),
        UsageLimit(kind: "weekly_all", percent: 37, severity: "normal", resetsAt: resets(in: 70), modelName: nil),
        UsageLimit(kind: "weekly_scoped", percent: 6, severity: "normal", resetsAt: resets(in: 70), modelName: "Fable"),
    ])

    static let hot = PreviewScenario(name: "hot", limits: [
        UsageLimit(kind: "session", percent: 96, severity: "critical", resetsAt: resets(in: 0.6), modelName: nil),
        UsageLimit(kind: "weekly_all", percent: 81, severity: "warning", resetsAt: resets(in: 30), modelName: nil),
        UsageLimit(kind: "weekly_scoped", percent: 64, severity: "normal", resetsAt: resets(in: 30), modelName: "Fable"),
    ])

    /// The 2026-10-09 shape: the Second account signed in and driving the menu
    /// bar, the Main account signed out on this Mac with its last numbers, its
    /// 5h window already reset and no Fable window ever observed.
    private static func pair(second: AccountUsage = second) -> [AccountUsage] { [second, main] }

    private static let second = AccountUsage(id: "acct2", label: "Second account", email: "abhaynihal200@gmail.com",
                                             status: "live", reason: nil, windows: [
        UsageLimit(kind: "session", percent: 13, severity: "normal", resetsAt: resets(in: 3.9), modelName: nil),
        UsageLimit(kind: "weekly_all", percent: 3, severity: "normal", resetsAt: resets(in: 34), modelName: nil),
        UsageLimit(kind: "weekly_scoped", percent: 1, severity: "normal", resetsAt: resets(in: 34), modelName: "Fable"),
    ], observedAt: Date().addingTimeInterval(-90))

    private static let main = AccountUsage(id: "acct1", label: "Main account", email: "abhaynihal2004@gmail.com",
                                           status: "removed-needs-reauth",
                                           reason: "Signed out of ~/.claude 2026-10-09 10:05 CDT; not restored", windows: [
        UsageLimit(kind: "session", percent: 4, severity: "normal", resetsAt: resets(in: -0.4), modelName: nil),
        UsageLimit(kind: "weekly_all", percent: 99, severity: "normal", resetsAt: resets(in: 7), modelName: nil),
    ], observedAt: Date().addingTimeInterval(-55 * 60))

    static let accounts = PreviewScenario(name: "accounts", accounts: pair())

    static let mainPicked = PreviewScenario(name: "main picked", accounts: pair(), menuBarAccount: "acct1")

    /// The poller missed three polls while the Second account ran hot.
    static let secondStale = PreviewScenario(name: "second stale", accounts: pair(second: AccountUsage(
        id: "acct2", label: "Second account", email: "abhaynihal200@gmail.com", status: "live", reason: nil, windows: [
            UsageLimit(kind: "session", percent: 84, severity: "warning", resetsAt: resets(in: 1.2), modelName: nil),
            UsageLimit(kind: "weekly_all", percent: 41, severity: "normal", resetsAt: resets(in: 34), modelName: nil),
            UsageLimit(kind: "weekly_scoped", percent: 22, severity: "normal", resetsAt: resets(in: 34), modelName: "Fable"),
        ], observedAt: Date().addingTimeInterval(-22 * 60))))

    static let stale = PreviewScenario(name: "stale", limits: normal.limits, error: "Usage API returned 429", stale: true)

    static let unavailable = PreviewScenario(name: "unavailable", error: "Session expired — run /login")

    var monitor: LimitsMonitor {
        LimitsMonitor(frozen: limits, error: error, stale: stale, accounts: accounts,
                      account: accounts.isEmpty ? nil : "acct2", menuBarAccount: menuBarAccount)
    }
}

// MARK: - Window

enum PreviewHarness {

    static var isEnabled: Bool { !(ProcessInfo.processInfo.environment["PERCH_UI_PREVIEW"] ?? "").isEmpty }

    private static var window: NSWindow?

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

    /// Owl frames sampled from the real motion curves, on a dark bar, to show the
    /// animation survives the trim: a swivel, a blink and the alert startle.
    private struct Filmstrip: View {
        private static let moves: [(String, OwlMove, Bool)] = [
            ("swivel", OwlMotion.swivel(toward: 1), false),
            ("blink", OwlMotion.blink(double: false), false),
            ("startle", OwlMotion.startle(), true),
        ]

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Self.moves, id: \.0) { name, move, alert in
                    HStack(spacing: 2) {
                        Text(name.uppercased())
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .frame(width: 58, alignment: .leading)
                        ForEach(0..<7, id: \.self) { i in
                            let t = move.duration * Double(i) / 6
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
    static func present() {
        let gap: CGFloat = 26
        let scenarios = PreviewScenario.all
        let width = (UsagePopup.panelWidth + gap) * CGFloat(scenarios.count) + gap
        let height: CGFloat = 720

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
                            .foregroundStyle(Color.white.opacity(0.3))
                    }
                    .frame(width: UsagePopup.panelWidth, alignment: .top)
                }
            }
            Filmstrip()
        }
        .padding(gap)
        .frame(width: width, height: height, alignment: .topLeading)
        // A flat mid-grey, not black: the panel's material is translucent and
        // over pure black every surface token reads darker than it ships.
        .background(Color(hex: 0x3A3A42))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Perch — UI preview"
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
