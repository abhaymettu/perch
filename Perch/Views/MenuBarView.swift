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

    init(page: Page = .main) {
        _page = State(initialValue: page)
    }

    /// Comma-joined section titles. A Set is not @AppStorage-encodable and a
    /// five-item list does not justify a Codable wrapper.
    @AppStorage("collapsedSections") private var collapsedRaw = ""

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

    /// The wordmark is the least useful text in here — you know which app you
    /// just opened. It stays small and muted; the status pill on the right is
    /// what the header is actually for, and it is the panel's only always-on
    /// colour.
    var header: some View {
        HStack(spacing: 9) {
            AnimatedOwlHead(size: 22, event: appState.lastEvent)
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.06), in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.07)))

            Text("Perch")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.inkMuted)

            Spacer()

            statusPill
        }
        .padding(.horizontal, 14)
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
                AnimatedOwlHead(size: 48, event: .scanning)
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
            ScrollView {
                VStack(spacing: 10) {
                    claudeSection
                    serverSection
                    daemonSection
                    cronSection
                    simulatorSection
                }
                .padding(12)
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
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }

    var claudeSection: some View {
        section("CLAUDE", icon: "brain", items: appState.sessions) { session in
            ClaudeSessionRowView(session: session)
        }
    }

    var serverSection: some View {
        section(
            "DEV SERVERS",
            icon: "server.rack",
            items: appState.servers,
            action: appState.servers.count > 1 ? "Stop All" : nil,
            perform: { appState.stopAllServers() }
        ) { server in
            ServerRowView(server: server)
        }
    }

    var daemonSection: some View {
        section("DAEMONS", icon: "gearshape.2", items: appState.agents) { agent in
            LaunchAgentRowView(agent: agent)
        }
    }

    var cronSection: some View {
        section("CRON", icon: "clock", items: appState.cronJobs) { job in
            CronJobRowView(job: job)
        }
    }

    var simulatorSection: some View {
        section(
            "SIMULATORS",
            icon: "iphone",
            items: appState.simulators,
            action: appState.simulators.count > 1 ? "Shut Down All" : nil,
            perform: { appState.shutDownAllSimulators() }
        ) { simulator in
            SimulatorRowView(simulator: simulator)
        }
    }

    @ViewBuilder
    func section<Item: Identifiable, Row: View>(
        _ title: String,
        icon: String,
        items: [Item],
        action: String? = nil,
        perform: @escaping () -> Void = {},
        @ViewBuilder row: @escaping (Item) -> Row
    ) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                sectionHeader(title, icon: icon, count: items.count, action: action, perform: perform)

                if !isCollapsed(title) {
                    VStack(spacing: 1) {
                        ForEach(items) { item in
                            row(item)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .move(edge: .trailing).combined(with: .opacity)
                                ))
                        }
                    }
                    .panelCard()
                }
            }
        }
    }

    func sectionHeader(
        _ title: String,
        icon: String,
        count: Int,
        action: String?,
        perform: @escaping () -> Void
    ) -> some View {
        let collapsed = isCollapsed(title)

        return HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 8.5, weight: .medium))
                .frame(width: 11)
                .foregroundStyle(Color.inkFaint)

            Text(title)
                .font(.sectionLabel)
                .tracking(1.1)
                .foregroundStyle(Color.inkFaint)

            // The count is always on. Knowing there are 25 daemons without
            // having to collapse the section to find out is the point.
            Text(verbatim: "\(count)")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.inkFaint.opacity(0.75))
                .monospacedDigit()

            // Only the chevron rotates; a hidden affordance you have to hover to
            // find is worse than a small one that is always there.
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Color.inkFaint.opacity(0.7))
                .rotationEffect(.degrees(collapsed ? -90 : 0))

            Spacer()

            if let action, !collapsed {
                Button(action: perform) {
                    Text(action)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Color.alert)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        // Lines up with the row text above and below it, which it did not.
        .padding(.horizontal, HoverRowStyle.horizontalPadding)
        .padding(.top, 6)
        .padding(.bottom, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.2)) { toggleCollapsed(title) }
        }
    }

    // MARK: - Collapse

    func isCollapsed(_ title: String) -> Bool {
        collapsedRaw.split(separator: ",").contains(Substring(title))
    }

    func toggleCollapsed(_ title: String) {
        var titles = collapsedRaw.split(separator: ",").map(String.init)
        if let index = titles.firstIndex(of: title) {
            titles.remove(at: index)
        } else {
            titles.append(title)
        }
        collapsedRaw = titles.joined(separator: ",")
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
