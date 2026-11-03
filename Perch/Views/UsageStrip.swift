import AppKit
import SwiftUI

/// The single-account panel: the signed-in account's week and model windows,
/// read from the usage endpoint. Clicking it opens the usage page.
struct UsageStrip: View {
    let monitor: LimitsMonitor
    let now: Date

    var body: some View {
        Button {
            guard let url = URL(string: "https://claude.ai/settings/usage") else { return }
            NSWorkspace.shared.open(url)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Claude")
                        .font(.system(size: 13, weight: .semibold))
                    if let model = monitor.model {
                        Text(model)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.inkFaint)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if monitor.isStale {
                        Label("Cached", systemImage: "clock")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.alert)
                    } else {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.inkFaint)
                            .accessibilityHidden(true)
                    }
                }

                if let week = monitor.headline {
                    WeekBlock(limit: week, now: now)
                        .padding(.top, 9)
                }
                ForEach(monitor.limits.filter { $0.modelName != nil }) { model in
                    ModelLine(limit: model, now: now)
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PanelRowButtonStyle())
        .help([Optional("Open usage settings"), monitor.error].compactMap { $0 }.joined(separator: " · "))
        .accessibilityHint("Open usage settings")
    }
}
