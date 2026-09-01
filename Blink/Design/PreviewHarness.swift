#if DEBUG
import SwiftUI

/// A frozen panel-full of state. `BLINK_UI_PREVIEW=1` renders one window with
/// every scenario side by side, so a design round is one screenshot and two
/// rounds are diffable. The live panel is a poor design surface: it needs Ice
/// quit, it is invisible to Accessibility, and its contents change under you.
struct PreviewScenario {
    let name: String
    var sessions: [ClaudeSession] = []
    var servers: [DevServer] = []
    var simulators: [Simulator] = []
    var agents: [LaunchAgent] = []
    var cronJobs: [CronJob] = []
    var limits: [UsageLimit] = []

    /// Settings and About get a column each, otherwise they are only ever seen
    /// by clicking through the live panel — which is how they stayed on the
    /// pre-redesign look for three rounds.
    var page: MenuBarView.Page = .main

    /// Six panels side by side are wider than the screen and two rows are
    /// taller than it, so a run renders one set: `main` or `pages`.
    var set: String = "main"

    /// Which screen of the `welcome` set to render. Ignored elsewhere.
    var step: Int = 0

    /// Port (not pid) -> restart failure. The only way to see `FailureBox`, which
    /// otherwise renders solely when a real relaunch dies.
    var restartFailures: [Int: String] = [:]
}

// MARK: - Scenarios

extension PreviewScenario {

    static let all: [PreviewScenario] = [
        busy, hot, quiet, empty, settings, about, welcome, welcomeAccess
    ]

    private static func ago(_ hours: Double) -> Date {
        Date().addingTimeInterval(-hours * 3600)
    }

    private static func resets(in hours: Double) -> Date {
        Date().addingTimeInterval(hours * 3600)
    }

    /// A normal working afternoon — the state the panel is in 95% of the time,
    /// so it is the one that has to be beautiful rather than merely legible.
    static let busy = PreviewScenario(
        name: "busy",
        sessions: [
            ClaudeSession(id: "lane:api", pid: 4102, kind: .remoteControl, name: "api",
                          workingDirectory: "/Users/dev", startedAt: ago(38),
                          childCount: 1, activeSince: ago(0.62)),
            ClaudeSession(id: "lane:docs", pid: 4110, kind: .remoteControl, name: "docs",
                          workingDirectory: "/Users/dev/docs", startedAt: ago(38),
                          childCount: 0, activeSince: nil),
            ClaudeSession(id: "lane:infra", pid: 4118, kind: .remoteControl, name: "infra",
                          workingDirectory: "/Users/dev/infra", startedAt: ago(38),
                          childCount: 1, activeSince: ago(2.4)),
            ClaudeSession(id: "interactive:9821", pid: 9821, kind: .interactive, name: "Blink",
                          workingDirectory: "/Users/dev/code/blink",
                          startedAt: ago(1.3), childCount: 3, activeSince: nil),
            ClaudeSession(id: "headless:7734", pid: 7734, kind: .headless, name: "Nightly Digest",
                          workingDirectory: "/Users/dev/code",
                          startedAt: ago(2.1), childCount: 0, activeSince: nil)
        ],
        servers: [
            DevServer(pid: 3301, port: 3000, command: "next dev", framework: .nextjs,
                      projectName: "Storefront", projectPath: "/Users/dev/storefront"),
            DevServer(pid: 3388, port: 5173, command: "vite", framework: .vite,
                      projectName: "Dashboard", projectPath: "/Users/dev/dashboard")
        ],
        simulators: [
            Simulator(udid: "A1", name: "iPhone 17 Pro", runtime: "iOS 26.0",
                      runningApp: .init(bundleID: "com.example.fieldkit", displayName: "FieldKit"))
        ],
        agents: [
            LaunchAgent(label: "com.example.tunnel", pid: 812, lastExitStatus: 0,
                        schedule: nil, plistPath: "/Users/dev/Library/LaunchAgents/com.example.tunnel.plist"),
            LaunchAgent(label: "com.example.backup", pid: nil, lastExitStatus: 0,
                        schedule: "every 30 min", plistPath: "/Users/dev/Library/LaunchAgents/bb.plist"),
            LaunchAgent(label: "com.example.fieldkit-sweep", pid: nil, lastExitStatus: 0,
                        schedule: "daily 09:00", plistPath: "/Users/dev/Library/LaunchAgents/ns.plist")
        ],
        limits: [
            UsageLimit(kind: "session", percent: 7, severity: "normal",
                       resetsAt: resets(in: 2.4), modelName: nil),
            UsageLimit(kind: "weekly_all", percent: 45, severity: "normal",
                       resetsAt: resets(in: 71), modelName: nil),
            UsageLimit(kind: "weekly_scoped", percent: 41, severity: "normal",
                       resetsAt: resets(in: 71), modelName: "Fable")
        ]
    )

    /// The colour paths real data never reaches: a critical window, a warning
    /// window, a failed daemon, and a headless session past its stale mark.
    static let hot = PreviewScenario(
        name: "hot",
        sessions: [
            ClaudeSession(id: "headless:7734", pid: 7734, kind: .headless, name: "Nightly Digest",
                          workingDirectory: "/Users/dev/code",
                          startedAt: ago(17.2), childCount: 0, activeSince: nil),
            ClaudeSession(id: "lane:data", pid: 4130, kind: .remoteControl, name: "data",
                          workingDirectory: "/Users/dev/data", startedAt: ago(40),
                          childCount: 1, activeSince: ago(14.6))
        ],
        servers: [
            DevServer(pid: 3301, port: 3000, command: "next dev", framework: .nextjs,
                      projectName: "Storefront", projectPath: "/Users/dev/storefront")
        ],
        agents: [
            LaunchAgent(label: "com.example.tunnel", pid: nil, lastExitStatus: 78,
                        schedule: nil, plistPath: "/Users/dev/Library/LaunchAgents/com.example.tunnel.plist"),
            LaunchAgent(label: "com.example.backup", pid: 903, lastExitStatus: 0,
                        schedule: nil, plistPath: "/Users/dev/Library/LaunchAgents/bb.plist")
        ],
        cronJobs: [
            CronJob(schedule: "*/15 * * * *", command: "~/bin/backup")
        ],
        limits: [
            UsageLimit(kind: "session", percent: 94, severity: "critical",
                       resetsAt: resets(in: 0.7), modelName: nil),
            UsageLimit(kind: "weekly_all", percent: 81, severity: "warning",
                       resetsAt: resets(in: 26), modelName: nil),
            UsageLimit(kind: "weekly_scoped", percent: 88, severity: "warning",
                       resetsAt: resets(in: 26), modelName: "Opus")
        ],
        restartFailures: [
            3000: "Error: listen EADDRINUSE: address already in use :::3000\n    at Server.setupListenHandle [as _listen2] (node:net:1817:16)"
        ]
    )

    /// Two rows and a usage strip. The panel is a fixed 640pt tall, so this is
    /// where wasted vertical space is most obvious.
    static let quiet = PreviewScenario(
        name: "quiet",
        sessions: [
            ClaudeSession(id: "interactive:9821", pid: 9821, kind: .interactive, name: "Scratch",
                          workingDirectory: "/Users/dev/scratch",
                          startedAt: ago(0.4), childCount: 0, activeSince: nil)
        ],
        agents: [
            LaunchAgent(label: "com.example.tunnel", pid: 812, lastExitStatus: 0,
                        schedule: nil, plistPath: "/Users/dev/Library/LaunchAgents/com.example.tunnel.plist")
        ],
        limits: [
            UsageLimit(kind: "session", percent: 3, severity: "normal",
                       resetsAt: resets(in: 4.8), modelName: nil),
            UsageLimit(kind: "weekly_all", percent: 12, severity: "normal",
                       resetsAt: resets(in: 120), modelName: nil)
        ]
    )

    /// Nothing running, no usage data. The empty state is a first impression
    /// and it gets the whole panel to itself.
    static let empty = PreviewScenario(name: "empty")

    static let settings = PreviewScenario(name: "settings", page: .settings, set: "pages")
    static let about = PreviewScenario(name: "about", page: .about, set: "pages")

    /// The first-launch window. Nobody who has already run Blink will see it
    /// again — `hasLaunchedBefore` is set — but it is a fresh install's entire
    /// first impression, and it stayed on the stock system look for a long time.
    static let welcome = PreviewScenario(name: "welcome", set: "welcome")
    static let welcomeAccess = PreviewScenario(name: "welcome · access", set: "welcome", step: 1)
}

// MARK: - Window

enum PreviewHarness {

    /// `BLINK_UI_PREVIEW=1` renders the four state scenarios; `=pages` renders
    /// settings and about.
    private static var set: String {
        let value = ProcessInfo.processInfo.environment["BLINK_UI_PREVIEW"] ?? ""
        return value == "1" ? "main" : value
    }

    static var isEnabled: Bool { !set.isEmpty }

    private static var window: NSWindow?

    /// Lays every scenario out in one row and prints the window's frame in
    /// screencapture's coordinates (top-left origin), so a shell loop can
    /// `screencapture -R` it without hunting for a window id.
    static func present() {
        // Otherwise the harness inherits whatever sections were collapsed the
        // last time the real app ran, and half the rows never render.
        UserDefaults.standard.removeObject(forKey: "collapsedSections")

        let gap: CGFloat = 26
        let scenarios = PreviewScenario.all.filter { $0.set == set }
        let width = (MenuBarView.panelSize.width + gap) * CGFloat(scenarios.count) + gap
        // Tall enough for the fullest panel, and no taller than that: the grey
        // left under a short panel is the point — it is how a round shows
        // whether the panel actually sizes to its content.
        let height = MenuBarView.maxListHeight + 260

        let content = VStack(spacing: 0) {
            HStack(alignment: .top, spacing: gap) {
                ForEach(scenarios, id: \.name) { scenario in
                    VStack(spacing: 7) {
                        if scenario.set == "welcome" {
                            WelcomeView(step: scenario.step)
                        } else {
                            MenuBarView(page: scenario.page)
                                .environment(AppState(frozen: scenario))
                                .environment(ScrollActivity())
                                // The real panel asks SwiftUI for its *ideal*
                                // height (NSHostingController's
                                // `.preferredContentSize`). An HStack instead
                                // proposes one, which the ScrollView happily
                                // fills — so without this the harness shows
                                // every panel stretched and hides the thing
                                // being judged.
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Text(scenario.name.uppercased())
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .tracking(1.4)
                            .foregroundStyle(Color.white.opacity(0.3))
                    }
                    .frame(width: MenuBarView.panelWidth, alignment: .top)
                }
            }
            .padding(gap)
        }
        .frame(width: width, height: height, alignment: .top)
        // A flat mid-grey, not black: the panel's material is translucent and
        // over pure black every surface token reads darker than it ships.
        .background(Color(hex: 0x3A3A42))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Blink — UI preview"
        window.contentView = NSHostingView(rootView: content)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Self.window = window

        // AppKit's origin is bottom-left; screencapture's is top-left.
        if let screen = window.screen ?? NSScreen.main {
            let frame = window.frame
            let top = screen.frame.maxY - frame.maxY
            print("PREVIEW_RECT \(Int(frame.minX)),\(Int(top)),\(Int(frame.width)),\(Int(frame.height))")
            fflush(stdout)
        }
    }
}
#endif
