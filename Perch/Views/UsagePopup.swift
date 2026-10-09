import SwiftUI

/// The whole panel in the usage-only build: the session and weekly meters, a
/// start-at-login toggle and Quit. Nothing else is scanned or shown.
struct UsagePopup: View {
    static let panelWidth: CGFloat = 328
    static let minHeight: CGFloat = 120

    let monitor: LimitsMonitor

    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var height: CGFloat = minHeight

    var body: some View {
        VStack(spacing: 0) {
            if monitor.limits.isEmpty {
                placeholder
            } else {
                UsageStrip(monitor: monitor)
                    .padding(.horizontal, 9)
                    .padding(.top, 9)
                    .padding(.bottom, 10)
            }

            PerchHairline()
            footer
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
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.30), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .preferredColorScheme(.dark)
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

    /// Never a 0%: until a fetch succeeds there is no number to show.
    private var placeholder: some View {
        Text(monitor.error.map { "Usage unavailable · \($0)" } ?? "Reading usage…")
            .font(.system(size: 12))
            .foregroundStyle(monitor.error == nil ? Color.inkMuted : Color.alert)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 17)
            .padding(.vertical, 22)
    }

    private var footer: some View {
        HStack(spacing: 0) {
            Toggle("Start at login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .foregroundStyle(Color.inkMuted)
                .padding(.horizontal, 8)

            Spacer(minLength: 0)

            Button { NSApplication.shared.terminate(nil) } label: {
                Text("Quit")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.inkMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
            .buttonStyle(PerchPlainButtonStyle())
            .help("Quit Perch")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(minHeight: 41)
        .background(.white.opacity(0.025))
    }
}

private struct UsagePopupHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
