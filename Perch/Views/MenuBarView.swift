import AppKit
import SwiftUI

struct MenuBarView: View {
    static let panelWidth: CGFloat = 328
    static let minHeight: CGFloat = 232
    static let maxListHeight: CGFloat = 452
    static let panelSize = CGSize(width: panelWidth, height: 560)

    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var page: Page
    @State private var expanded: Set<String>
    @State private var listHeight: CGFloat = 300

    init(page: Page = .main, open: String? = nil) {
        _page = State(initialValue: page)
        _expanded = State(initialValue: Set(open.map { [$0] } ?? []))
    }

    enum Page {
        case main, settings, about
    }

    private func go(to destination: Page) {
        withAnimation(reduceMotion ? nil : panelPageChange) {
            page = destination
        }
        requestLayout()
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch page {
            case .main:
                mainPage.panelPage(offset: reduceMotion ? 0 : -24)
            case .settings:
                SettingsPage { go(to: .main) }
                    .panelPage(offset: reduceMotion ? 0 : 24)
            case .about:
                AboutPage { go(to: .main) }
                    .panelPage(offset: reduceMotion ? 0 : 24)
            }
        }
        .frame(width: Self.panelWidth)
        .frame(minHeight: Self.minHeight, alignment: .top)
        .integralHeight()
        .foregroundStyle(Color.ink)
        .tint(Color.ink)
        .background { PerchPanelShell() }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.30), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(0.44), location: 0.22),
                    .init(color: .white.opacity(0.78), location: 0.48),
                    .init(color: .white.opacity(0.24), location: 0.78),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)
            .padding(.horizontal, 12)
            .allowsHitTesting(false)
        }
        .preferredColorScheme(.dark)
        .onAppear { revealProblems() }
        .onChange(of: problemSections) { _, newValue in
            expanded.formUnion(newValue)
            requestLayout()
        }
        .onReceive(NotificationCenter.default.publisher(for: .perchPanelWillOpen)) { _ in
            expanded = Set(problemSections)
            page = .main
            requestLayout()
        }
    }
}

private extension MenuBarView {
    var mainPage: some View {
        VStack(spacing: 0) {
            header

            if !appState.usage.limits.isEmpty {
                UsageStrip(monitor: appState.usage)
                    .padding(.horizontal, 9)
                    .padding(.bottom, 10)
            }

            content
            PerchHairline()
            footer
        }
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Perch")
                .font(.system(size: 18, weight: .semibold))
                .tracking(-0.35)
                .frame(height: 23, alignment: .leading)

            HStack(spacing: 6) {
                PerchStatusMark(state: appState.hasProblem ? .warning : .healthy)
                    .frame(width: 14, height: 14)

                Text(appState.hasProblem ? "Needs attention" : "All clear")

                Spacer(minLength: 4)

                Text("\(appState.totalCount) running")
                    .foregroundStyle(Color.inkMuted)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .font(.system(size: 12))
            .foregroundStyle(appState.hasProblem ? Color.alert : Color.ink)
            .frame(height: 18)
            .accessibilityElement(children: .combine)
            .help(
                appState.hasProblem
                    ? "Something is stale or has failed"
                    : "Everything Perch watches is healthy"
            )
        }
        .padding(.horizontal, 17)
        .padding(.top, 18)
        .padding(.bottom, 15)
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
            watchingList
                .transition(.opacity)
        }
    }

    var watchingList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Watching")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.inkMuted)
                    .frame(height: 16)
                    .padding(.leading, 18)
                    .padding(.top, 3)
                    .padding(.bottom, 5)

                VStack(spacing: 0) {
                    ForEach(Array(sections.enumerated()), id: \.element.title) { index, section in
                        if index > 0 {
                            PerchHairline()
                                .padding(.horizontal, 10)
                        }
                        disclosure(section)
                    }
                }
                .perchGlassCard()
                .padding(.horizontal, 9)

                if let bridge = appState.bridge {
                    BridgeRowView(status: bridge)
                        .padding(.horizontal, 9)
                        .padding(.top, 10)
                }
            }
            .padding(.bottom, 12)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: PerchListHeightKey.self,
                        value: proxy.size.height
                    )
                }
            }
        }
        .frame(height: min(Self.maxListHeight, listHeight))
        .onPreferenceChange(PerchListHeightKey.self) { height in
            guard height > 0 else { return }
            let rounded = height.rounded(.up)
            guard rounded != listHeight else { return }
            listHeight = rounded
            requestLayout()
        }
    }

    func displayName(for section: RoostSection) -> String {
        switch section.title {
        case "CLAUDE": return "Claude sessions"
        case "DEV SERVERS": return "Dev servers"
        case "DAEMONS": return "Launch agents"
        case "CRON": return "Cron"
        case "SIMULATORS": return "Simulators"
        default: return section.title.capitalized
        }
    }

    func problemWord(for section: RoostSection) -> String {
        section.title == "CLAUDE" ? "stale" : "failed"
    }

    func disclosure(_ section: RoostSection) -> some View {
        let isOpen = expanded.contains(section.title) && section.count > 0

        return VStack(spacing: 0) {
            Button {
                toggle(section.title)
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: section.icon)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.inkMuted)
                        .frame(width: 18, height: 18)
                        .accessibilityHidden(true)

                    Text(displayName(for: section))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(section.count == 0 ? Color.inkMuted : Color.ink)
                        .lineLimit(1)

                    Spacer(minLength: 2)

                    if section.isAlert {
                        PerchStateLabel(word: problemWord(for: section), state: .warning)
                    }

                    Text("\(section.count)")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.inkMuted)
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.inkFaint)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 43)
                .contentShape(Rectangle())
            }
            .buttonStyle(PerchPlainButtonStyle())
            .disabled(section.count == 0)
            .accessibilityLabel(displayName(for: section))
            .accessibilityValue(
                "\(section.count)\(section.isAlert ? ", \(problemWord(for: section))" : ""), \(isOpen ? "expanded" : "collapsed")"
            )
            .accessibilityHint(isOpen ? "Collapse section" : "Expand section")
            .help(
                section.count == 0
                    ? "No \(displayName(for: section).lowercased())"
                    : "\(displayName(for: section))\(section.isAlert ? " — needs attention" : "")"
            )

            if isOpen {
                section.rows()
                    .padding(.leading, 27)
                    .padding(.trailing, 1)
                    .padding(.bottom, 9)
                    .transition(.opacity)
            }
        }
        .background(isOpen ? Color.black.opacity(0.12) : Color.clear)
    }

    func toggle(_ title: String) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            if expanded.contains(title) {
                expanded.remove(title)
            } else {
                expanded.insert(title)
            }
        }
        requestLayout()
    }

    var problemSections: [String] {
        sections.filter { $0.isAlert && $0.count > 0 }.map(\.title)
    }

    func revealProblems() {
        expanded.formUnion(problemSections)
        requestLayout()
    }

    func requestLayout() {
        NotificationCenter.default.post(name: .perchPanelLayoutChanged, object: nil)
    }

    var sections: [RoostSection] {
        [
            RoostSection(
                title: "CLAUDE",
                icon: "text.bubble",
                count: appState.sessions.count,
                isAlert: appState.sessions.contains(where: \.isStale),
                rows: {
                    card(appState.sessions) { ClaudeSessionRowView(session: $0) }
                }
            ),
            RoostSection(
                title: "DEV SERVERS",
                icon: "server.rack",
                count: appState.servers.count,
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
                title: "DAEMONS",
                icon: "gearshape",
                count: appState.agents.count,
                isAlert: appState.agents.contains(where: \.hasFailed),
                rows: {
                    card(appState.agents) { LaunchAgentRowView(agent: $0) }
                }
            ),
            RoostSection(
                title: "CRON",
                icon: "clock",
                count: appState.cronJobs.count,
                isAlert: false,
                rows: {
                    card(appState.cronJobs) { CronJobRowView(job: $0) }
                }
            ),
            RoostSection(
                title: "SIMULATORS",
                icon: "iphone",
                count: appState.simulators.count,
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
            VStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    PerchHairline()
                        .padding(.horizontal, 9)
                    row(item)
                        .transition(.opacity)
                }

                if let action {
                    Button(action: perform) {
                        Text(action)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.ink)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.white.opacity(0.06))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(.white.opacity(0.17), lineWidth: 1)
                                    }
                            }
                    }
                    .buttonStyle(PerchPlainButtonStyle())
                    .padding(.leading, 9)
                    .padding(.top, 5)
                    .help(action)
                }
            }
        )
    }

    var footer: some View {
        HStack(spacing: 0) {
            footerButton("Settings…") { go(to: .settings) }
            footerButton("About Perch") { go(to: .about) }
            Spacer(minLength: 0)
            footerButton("Quit") { NSApplication.shared.terminate(nil) }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(minHeight: 41)
        .background(.white.opacity(0.025))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Application actions")
    }

    func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Color.inkMuted)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
        .buttonStyle(PerchPlainButtonStyle())
        .help(title == "Quit" ? "Quit Perch" : title)
    }
}

struct RoostSection {
    let title: String
    let icon: String
    let count: Int
    let isAlert: Bool
    let rows: () -> AnyView
}

private struct PerchListHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct IntegralHeight: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let size = subview.sizeThatFits(proposal)
        return CGSize(width: size.width, height: size.height.rounded(.up))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(
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