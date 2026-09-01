import SwiftUI

struct MenuBarView: View {
    static let panelWidth: CGFloat = 328

    /// The panel is as tall as what is running. A fixed 640 left half the panel
    /// as empty black on a quiet afternoon, which is most afternoons.
    static let minHeight: CGFloat = 232
    static let maxListHeight: CGFloat = 452

    /// The panel opens at full height before SwiftUI reports its real one; this
    /// is only the first frame's guess.
    static let panelSize = CGSize(width: panelWidth, height: 560)

    @Environment(AppState.self) private var appState

    @State private var page: Page

    init(page: Page = .main, open: String? = nil) {
        _page = State(initialValue: page)
        _open = State(initialValue: open)
    }

    /// The one section showing its rows, by title, or nil for the bare glance.
    /// One at a time on purpose: five sections that can all be open is how the
    /// panel became five stacked lists. Not persisted — the panel opens as a
    /// glance every time, and the glance is the roost.
    @State private var open: String?

    enum Page {
        case main, settings, about
    }

    private func go(to destination: Page) {
        withAnimation(panelPageChange) { page = destination }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch page {
            case .main:
                mainPage.panelPage(offset: -24)
            case .settings:
                SettingsPage { go(to: .main) }.panelPage(offset: 24)
            case .about:
                AboutPage { go(to: .main) }.panelPage(offset: 24)
            }
        }
        .frame(width: Self.panelWidth)
        .frame(minHeight: Self.minHeight, alignment: .top)
        // Material alone takes the wallpaper's colour; the ground pins the
        // panel to something the wallpaper only tints.
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.panelGround.opacity(0.80))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onReceive(NotificationCenter.default.publisher(for: .perchPanelWillOpen)) { _ in
            open = nil
            page = .main
        }
    }
}

// MARK: - Main page

private extension MenuBarView {

    var mainPage: some View {
        VStack(spacing: 0) {
            header
            PanelDivider()

            if !appState.usage.limits.isEmpty {
                UsageStrip(monitor: appState.usage)
                PanelDivider()
            }

            content
            PanelDivider()
            footer
        }
    }

    /// The owl lives in the menu bar, where you actually look at it. In here it
    /// was a second copy of a mark you had just clicked, so the header is the
    /// wordmark and the status pill — the name set as a name rather than as a
    /// muted caption beside a logo.
    var header: some View {
        HStack(spacing: 9) {
            Text("Perch")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(Color.ink)

            Spacer()

            statusPill
        }
        .padding(.horizontal, 12)
        .padding(.top, 11)
        .padding(.bottom, 10)
    }

    var statusPill: some View {
        let problem = appState.hasProblem
        let idle = appState.totalCount == 0
        let tint: Color = problem ? .alert : (idle ? .inkFaint : .ok)
        let text = idle ? "idle" : "\(appState.totalCount) running"

        return HStack(spacing: 5) {
            Circle()
                .fill(tint)
                .frame(width: 5, height: 5)

            Text(text)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(problem ? Color.alert : Color.ink)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(0.13), in: Capsule())
        .help(problem ? "Something is stale or has failed" : "Everything Perch watches is healthy")
    }

    @ViewBuilder
    var content: some View {
        if appState.isInitialLoad {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                Text("Scanning...")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 150)
            .transition(.opacity)
        } else if !appState.hasAnything {
            EmptyStateView()
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        } else {
            VStack(spacing: 0) {
                roost
                openSection
            }
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }

    // MARK: - The roost

    /// Five perches in one strip: a glyph, a count, and a health tint each.
    /// Stacked closed section headers read as five lists you have not opened;
    /// one strip of five reads as the instrument the panel actually is. The
    /// touched perch widens to carry its own name, so the open section is
    /// labelled without spending a second row on a header.
    var roost: some View {
        HStack(spacing: 5) {
            ForEach(sections, id: \.title) { perch($0) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    func perch(_ section: RoostSection) -> some View {
        let isOpen = open == section.title
        let tint: Color = section.isAlert ? .alert
            : (section.count == 0 ? .inkFaint : (isOpen ? .ink : .inkMuted))

        return HStack(spacing: 5) {
            Image(systemName: section.icon)
                .font(.system(size: 9.5, weight: .medium))
                .frame(width: 12)

            if isOpen {
                Text(section.title)
                    .font(.sectionLabel)
                    .tracking(1.1)
                    .fixedSize()
            }

            Text(verbatim: "\(section.count)")
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .contentTransition(.numericText())
                .opacity(section.count == 0 ? 0.5 : 1)
                // A count that truncates is worse than no count: the open
                // chip carries a label too, and without this the digit is the
                // flexible child the HStack squeezes to nothing.
                .fixedSize()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(
            Capsule().fill(Color.white.opacity(isOpen ? 0.10 : 0.045))
        )
        .contentShape(Capsule())
        // An empty perch is a readout, not a control: tapping it would morph
        // the strip and open nothing.
        .allowsHitTesting(section.count > 0)
        .onTapGesture { toggle(section.title) }
        .help(section.count == 0 ? "No \(section.title.lowercased())" : section.title.capitalized)
    }

    /// One section's rows, and its bulk action as the last row of the same card
    /// — the strip has no width left for it, and a "stop all" belongs with the
    /// things it stops rather than in the chrome above them.
    @ViewBuilder
    var openSection: some View {
        if let section = sections.first(where: { $0.title == open }), section.count > 0 {
            ScrollView {
                section.rows()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.965),
                        .init(color: .black.opacity(0.55), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(maxHeight: Self.maxListHeight)
            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
        }
    }

    /// Tapping the open perch closes it; tapping another moves the expansion.
    func toggle(_ title: String) {
        // Critically damped: the strip morphs and the card arrives under it in
        // one motion, and an impatient second tap redirects it mid-flight.
        withAnimation(.spring(response: 0.32, dampingFraction: 1)) {
            open = (open == title) ? nil : title
        }
        // The window resize is AppKit's, not SwiftUI's, so it has to be told.
        // Waiting for the 1s poll is what made it land as a jump.
        NotificationCenter.default.post(name: .perchPanelLayoutChanged, object: nil)
    }

    // MARK: - Sections

    var sections: [RoostSection] {
        [
            RoostSection(
                title: "CLAUDE", icon: "bubble.left.and.bubble.right", count: appState.sessions.count,
                isAlert: appState.sessions.contains(where: \.isStale),
                rows: { card(appState.sessions) { ClaudeSessionRowView(session: $0) } }
            ),
            RoostSection(
                title: "DEV SERVERS", icon: "server.rack", count: appState.servers.count,
                isAlert: appState.restartStates.values.contains { if case .failed = $0 { true } else { false } },
                rows: {
                    card(appState.servers, action: appState.servers.count > 1 ? "Stop All" : nil,
                         perform: { appState.stopAllServers() }) { ServerRowView(server: $0) }
                }
            ),
            RoostSection(
                title: "DAEMONS", icon: "gearshape.2", count: appState.agents.count,
                isAlert: appState.agents.contains(where: \.hasFailed),
                rows: { card(appState.agents) { LaunchAgentRowView(agent: $0) } }
            ),
            RoostSection(
                title: "CRON", icon: "clock", count: appState.cronJobs.count,
                isAlert: false,
                rows: { card(appState.cronJobs) { CronJobRowView(job: $0) } }
            ),
            RoostSection(
                title: "SIMULATORS", icon: "iphone", count: appState.simulators.count,
                isAlert: appState.simulatorRestartStates.values.contains { if case .failed = $0 { true } else { false } },
                rows: {
                    card(appState.simulators, action: appState.simulators.count > 1 ? "Shut Down All" : nil,
                         perform: { appState.shutDownAllSimulators() }) { SimulatorRowView(simulator: $0) }
                }
            )
        ]
    }

    func card<Item: Identifiable, Row: View>(
        _ items: [Item],
        action: String? = nil,
        perform: @escaping () -> Void = {},
        @ViewBuilder row: @escaping (Item) -> Row
    ) -> AnyView {
        AnyView(
            VStack(spacing: 1) {
                ForEach(items) { item in
                    row(item)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                }

                if let action {
                    Button(action: perform) {
                        Text(action)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.alert)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, HoverRowStyle.horizontalPadding)
                            .frame(height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .panelCard()
        )
    }

    /// One 30pt strip rather than three stacked rows: the list above it is the
    /// reason the panel exists, and it was losing 100pt to navigation. Bare
    /// glyphs, not filled circles — three grey pills in a corner read as an
    /// unrelated widget stuck to the panel.
    var footer: some View {
        HStack(spacing: 0) {
            FooterAction(symbol: "gearshape", help: "Settings") { go(to: .settings) }
            FooterAction(symbol: "info.circle", help: "About") { go(to: .about) }

            Spacer()

            FooterAction(symbol: "power", help: "Quit Perch", hoverTint: .alert) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
    }
}

// MARK: - Section descriptor

/// One perch's worth of state. The strip and the open card read from the same
/// five values, so a count in the strip cannot disagree with the rows below it.
struct RoostSection {
    let title: String
    let icon: String
    let count: Int
    let isAlert: Bool
    let rows: () -> AnyView
}
