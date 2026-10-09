import AppKit
import SwiftUI

struct UsageStrip: View {
    let monitor: LimitsMonitor

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button {
            guard let url = URL(string: "https://claude.ai/settings/usage") else { return }
            NSWorkspace.shared.open(url)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                caption

                // On a clock, so a reset that passes between polls shows as passed.
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    HStack(alignment: .top, spacing: 13) {
                        ForEach(monitor.limits) { limit in
                            UsageColumn(limit: limit, now: context.date)
                        }
                    }
                }
                .padding(.top, 12)

                if monitor.isStale || monitor.error != nil {
                    PerchHairline()
                        .padding(.top, 10)
                        .padding(.bottom, 8)
                    freshness
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(isHovered ? 0.045 : 0))
            .perchGlassCard(radius: 11)
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.13), value: isHovered)
        .help(
            [Optional("Open usage settings"), monitor.error]
                .compactMap { $0 }
                .joined(separator: " · ")
        )
        .accessibilityLabel(
            "\(monitor.isStale ? "Cached usage" : "Usage")\(monitor.model.map { " for \($0)" } ?? "")"
        )
        .accessibilityValue(accessibilitySummary)
        .accessibilityHint("Open usage settings")
    }

    private var caption: some View {
        HStack(spacing: 6) {
            Text("Usage")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ink)

            Spacer(minLength: 4)

            if let model = monitor.model {
                Text(model)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.inkMuted)
                    .lineLimit(1)
            }

            Image(systemName: "arrow.up.right")
                .font(.system(size: 10))
                .foregroundStyle(Color.inkMuted)
                .accessibilityHidden(true)
        }
        .frame(height: 17)
    }

    @ViewBuilder
    private var freshness: some View {
        if monitor.isStale {
            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.system(size: 11))
                    .accessibilityHidden(true)
                // The supplied monitor interface exposes staleness, not a
                // successful-fetch timestamp. Never invent an update age.
                Text("Cached")
                    .font(.system(size: 11))
            }
            .foregroundStyle(Color.inkMuted)
            .help(monitor.error ?? "Showing cached usage")
        } else if let error = monitor.error {
            HStack(alignment: .top, spacing: 5) {
                PerchStatusMark(state: .warning)
                Text("Unavailable · \(error)")
                    .font(.system(size: 11))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color.alert)
            .help(error)
        }
    }

    private var accessibilitySummary: String {
        var parts = monitor.limits.map {
            "\($0.shortTitle) \($0.percent) percent" + ($0.countdown().isEmpty ? "" : ", resets in \($0.countdown())")
        }
        if monitor.isStale { parts.append("Cached") }
        if let error = monitor.error { parts.append(error) }
        return parts.joined(separator: ", ")
    }
}