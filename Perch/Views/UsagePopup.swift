import SwiftUI

/// The whole panel: one section per account (or the single signed-in
/// account's windows), then a footer with freshness and the app's few
/// settings. Nothing else is scanned or shown.
struct UsagePopup: View {
    static let panelWidth: CGFloat = 316
    static let minHeight: CGFloat = 96

    let monitor: LimitsMonitor

    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var height: CGFloat = minHeight

    var body: some View {
        // The file changes every 300 s, but a window can roll over between
        // polls, and ages have to keep counting.
        TimelineView(.periodic(from: .now, by: 15)) { context in
            VStack(spacing: 0) {
                Group {
                    if monitor.isMultiAccount {
                        AccountCards(monitor: monitor, now: context.date)
                    } else if monitor.headline == nil {
                        placeholder
                    } else {
                        UsageStrip(monitor: monitor, now: context.date)
                    }
                }
                .padding(6)

                PerchHairline()
                footer(now: context.date)
            }
        }
        .frame(width: Self.panelWidth)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: UsagePopupHeightKey.self, value: proxy.size.height)
            }
        }
        .foregroundStyle(Color.ink)
        .tint(Color.ink)
        .background { PerchPanelShell() }
        .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                .strokeBorder(Color.panelStroke, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .onPreferenceChange(UsagePopupHeightKey.self) { value in
            guard value > 0 else { return }
            let rounded = value.rounded(.up)
            guard rounded != height else { return }
            height = rounded
            NotificationCenter.default.post(
                name: .perchPanelLayoutChanged, object: nil, userInfo: ["height": rounded]
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .perchPanelWillOpen)) { _ in
            launchAtLogin = LoginItem.isEnabled
        }
        .onChange(of: launchAtLogin) { _, enabled in
            do { try LoginItem.setEnabled(enabled) } catch { launchAtLogin = LoginItem.isEnabled }
        }
    }

    static let radius: CGFloat = 12

    /// Never a 0%: until a fetch succeeds there is no number to show.
    private var placeholder: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if monitor.error != nil {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .medium))
                    .accessibilityHidden(true)
            }
            Text(monitor.error.map { "Usage unavailable. \($0)" } ?? "Reading usage…")
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(monitor.error == nil ? Color.inkMuted : Color.alert)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 16)
    }

    private func footer(now: Date) -> some View {
        HStack(spacing: 8) {
            Text(freshness(now: now))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(Color.inkFaint)
                .lineLimit(1)

            Spacer(minLength: 0)

            Menu {
                Toggle("Start at Login", isOn: $launchAtLogin)
                Button("Open Usage Page") {
                    if let url = URL(string: "https://claude.ai/settings/usage") { NSWorkspace.shared.open(url) }
                }
                Divider()
                Button("Quit Perch") { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.inkMuted)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Settings and Quit")
            .accessibilityLabel("Settings")
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(height: 34)
    }

    /// When the newest reading landed. Per-account staleness is said on the
    /// account itself; this line is the panel's overall heartbeat.
    private func freshness(now: Date) -> String {
        guard monitor.isMultiAccount else {
            if monitor.isStale { return "Showing cached numbers" }
            return monitor.headline == nil ? "" : "Updated every 3 min"
        }
        let newest = monitor.accounts.filter { !$0.isSignedOut }.compactMap(\.observedAt).max()
        guard let newest else { return "No readings yet" }
        let minutes = max(0, Int(now.timeIntervalSince(newest)) / 60)
        return switch minutes {
        case ..<1:    "Updated just now"
        case ..<60:   "Updated \(minutes)m ago"
        case ..<1440: "Updated \(minutes / 60)h ago"
        default:      "Updated \(minutes / 1440)d ago"
        }
    }
}

private struct UsagePopupHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
