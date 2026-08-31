import SwiftUI

struct MenuBarView: View {
    static let panelSize = CGSize(width: 320, height: 560)

    @Environment(AppState.self) private var appState

    @State private var page: Page = .main

    /// Comma-joined section titles. A Set is not @AppStorage-encodable and a
    /// five-item list does not justify a Codable wrapper.
    @AppStorage("collapsedSections") private var collapsedRaw = ""

    enum Page {
        case main, settings, about
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            mainPage
                .panelPage(isActive: page == .main, restingOffset: -24)

            SettingsPage(isVisible: page == .settings) { page = .main }
                .frame(maxHeight: .infinity, alignment: .top)
                .panelPage(isActive: page == .settings, restingOffset: 24)

            AboutPage { page = .main }
                .frame(maxHeight: .infinity, alignment: .top)
                .panelPage(isActive: page == .about, restingOffset: 24)
        }
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
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

            if let block = appState.usage.block {
                UsageStrip(block: block)
                PanelDivider()
            }

            content
            PanelDivider()
            footer
        }
    }

    var header: some View {
        HStack {
            Text("Blink")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            if appState.totalCount > 0 {
                AnimatedRobotHead(size: 22, event: appState.lastEvent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    var content: some View {
        if appState.isInitialLoad {
            VStack(spacing: 12) {
                AnimatedRobotHead(size: 48, event: .scanning)
                Text("Scanning...")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        } else if !appState.hasAnything {
            EmptyStateView()
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        } else {
            ScrollView {
                VStack(spacing: 12) {
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
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(title, icon: icon, count: items.count, action: action, perform: perform)

                if !isCollapsed(title) {
                    ForEach(items) { item in
                        row(item)
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            ))
                    }
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

        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .frame(width: 12)
                .foregroundStyle(.secondary.opacity(0.6))

            Text(title)
                .font(.system(size: 10, weight: .medium))
                .tracking(0.8)
                .foregroundStyle(.secondary.opacity(0.6))

            if collapsed {
                Text(verbatim: "\(count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.45))
            }

            Spacer()

            if let action, !collapsed {
                Button(action: perform) {
                    Text(action)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.alert)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }

            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.5))
                .rotationEffect(.degrees(collapsed ? -90 : 0))
        }
        .padding(.horizontal, 4)
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

    var footer: some View {
        VStack(spacing: 0) {
            PanelRow("Settings") { page = .settings }
            PanelDivider()
            PanelRow("About") { page = .about }
            PanelDivider()
            PanelRow("Quit") { NSApplication.shared.terminate(nil) }
        }
    }
}
