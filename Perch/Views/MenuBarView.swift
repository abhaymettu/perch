import AppKit
import SwiftUI

struct MenuBarView: View {
    static let panelWidth: CGFloat = 328

    // Quiet days should not leave a tall, empty window on screen.
    static let minHeight: CGFloat = 232
    static let maxListHeight: CGFloat = 452

    // AppKit needs an initial size before SwiftUI can measure the contents.
    static let panelSize = CGSize(width: panelWidth, height: 560)

    @Environment(AppState.self) private var appState
    @State private var page: Page
    @State private var open: String?

    init(page: Page = .main, open: String? = nil) {
        _page = State(initialValue: page)
        _open = State(initialValue: open)
    }

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
        .integralHeight()
        .foregroundStyle(Color.ink)
        .background(Color.panelGround)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.panelRule, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .perchPanelWillOpen)) { _ in
            open = nil
            page = .main
        }
    }
}

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

    var header: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.terracotta)
                .frame(width: 3, height: 14)
                .accessibilityHidden(true)

            Text("Perch")
                .font(.panelTitle)
                .foregroundStyle(Color.ink)

            Spacer(minLength: 8)
            statusPill
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
    }

    var statusPill: some View {
        let problem = appState.hasProblem
        let idle = appState.totalCount == 0
        let tint: Color = problem ? .alert : (idle ? .inkFaint : .ok)
        let count = idle ? "idle" : "\(appState.totalCount) running"
        let text = problem ? "\(count) · check" : count

        return HStack(spacing: 5) {
            Circle()
                .fill(tint)
                .frame(width: 5, height: 5)
                .accessibilityHidden(true)

            Text(text)
                .font(.system(size: 10.5, weight: problem ? .semibold : .medium))
                .foregroundStyle(problem ? Color.alert : Color.inkMuted)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .help(problem ? "Something is stale or has failed" : "Everything Perch watches is healthy")
    }

    @ViewBuilder
    var content: some View {
        if appState.isInitialLoad {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                Text("Scanning…")
                    .font(.rowTitle)
                    .foregroundStyle(Color.inkMuted)
            }
            .frame(maxWidth: .infinity, minHeight: 150)
            .transition(.opacity)
        } else if !appState.hasAnything {
            EmptyStateView()
                .transition(.opacity)
        } else {
            VStack(spacing: 0) {
                roost
                bridgeLine
                openSection
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    var bridgeLine: some View {
        if let bridge = appState.bridge {
            BridgeRowView(status: bridge)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
        }
    }

    // Stable columns keep all five sections visible when a long-named section
    // opens. The underline, rather than a tint alone, identifies the selection.
    var roost: some View {
        HStack(spacing: 4) {
            ForEach(sections, id: \.title) { section in
                perch(section)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    func shortName(for section: RoostSection) -> String {
        switch section.title {
        case "CLAUDE": "Claude"
        case "DEV SERVERS": "Servers"
        case "DAEMONS": "Agents"
        case "CRON": "Cron"
        case "SIMULATORS": "Sims"
        default: section.title.capitalized
        }
    }

    func perch(_ section: RoostSection) -> some View {
        let isOpen = open == section.title
        let tint: Color = section.isAlert ? .alert
            : (section.count == 0 ? .inkFaint : .ink)

        return Button {
            toggle(section.title)
        } label: {
            VStack(spacing: 1) {
                HStack(spacing: 3) {
                    Image(systemName: section.icon)
                        .font(.system(size: 10, weight: .medium))

                    Text(verbatim: "\(section.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    if section.isAlert {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 7, weight: .bold))
                    }
                }
                .frame(height: 14)

                Text(shortName(for: section))
                    .font(.system(size: 9, weight: isOpen ? .semibold : .regular))
                    .lineLimit(1)
                    .frame(height: 11)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 3)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(isOpen ? Color.panelSurface : Color.panelGround)
            .overlay(alignment: .bottom) {
                if isOpen {
                    Rectangle()
                        .fill(Color.terracotta)
                        .frame(height: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(section.count == 0)
        .accessibilityLabel(section.title.capitalized)
        .accessibilityValue(
            "\(section.count)\(section.isAlert ? ", needs attention" : "")\(isOpen ? ", expanded" : ", collapsed")"
        )
        .help(
            section.count == 0
                ? "No \(section.title.lowercased())"
                : "\(section.title.capitalized)\(section.isAlert ? " — needs attention" : "")"
        )
    }

    @ViewBuilder
    var openSection: some View {
        if let section = sections.first(where: { $0.title == open }), section.count > 0 {
            ScrollView {
                section.rows()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
            .frame(maxHeight: Self.maxListHeight)
            .transition(.opacity)
        }
    }

    func toggle(_ title: String) {
        withAnimation(.spring(response: 0.32, dampingFraction: 1)) {
            open = (open == title) ? nil : title
        }

        // The window belongs to AppKit, so a section change must also request
        // a window measurement rather than waiting for the next data poll.
        NotificationCenter.default.post(name: .perchPanelLayoutChanged, object: nil)
    }

    var sections: [RoostSection] {
        [
            RoostSection(
                title: "CLAUDE", icon: "bubble.left.and.bubble.right",
                count: appState.sessions.count,
                isAlert: appState.sessions.contains(where: \.isStale),
                rows: { card(appState.sessions) { ClaudeSessionRowView(session: $0) } }
            ),
            RoostSection(
                title: "DEV SERVERS", icon: "server.rack", count: appState.servers.count,
                isAlert: appState.restartStates.values.contains {
                    if case .failed = $0 { true } else { false }
                },
                rows: {
                    card(
                        appState.servers,
                        action: appState.servers.count > 1 ? "Stop All" : nil,
                        perform: { appState.stopAllServers() }
                    ) { ServerRowView(server: $0) }
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
                isAlert: appState.simulatorRestartStates.values.contains {
                    if case .failed = $0 { true } else { false }
                },
                rows: {
                    card(
                        appState.simulators,
                        action: appState.simulators.count > 1 ? "Shut Down All" : nil,
                        perform: { appState.shutDownAllSimulators() }
                    ) { SimulatorRowView(simulator: $0) }
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
                    PanelRowDivider()

                    Button(action: perform) {
                        Text(action)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.alert)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, HoverRowStyle.horizontalPadding)
                            .frame(height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .panelCard()
        )
    }

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

// The strip and the list share one descriptor so their counts cannot disagree.
struct RoostSection {
    let title: String
    let icon: String
    let count: Int
    let isAlert: Bool
    let rows: () -> AnyView
}

// AppKit gives the hosting view whole-point heights. Rounding the ideal size
// prevents repeated layout requests for a height the window cannot provide.
private struct IntegralHeight: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews[0].sizeThatFits(proposal)
        return CGSize(width: size.width, height: size.height.rounded(.up))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(bounds.size)
        )
    }
}

extension View {
    func integralHeight() -> some View {
        IntegralHeight() { self }
    }
}
