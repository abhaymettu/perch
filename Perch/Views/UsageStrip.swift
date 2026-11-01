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

                HStack(alignment: .top, spacing: 13) {
                    ForEach(monitor.limits) { limit in
                        column(for: limit)
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

    private func column(for limit: UsageLimit) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(limit.shortTitle)
                .font(.system(size: 11))
                .foregroundStyle(Color.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(height: 15)

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(limit.percent)")
                    .font(.system(size: 23, weight: .medium))
                    .tracking(-0.55)
                    .foregroundStyle(Color.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())

                Text("%")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.inkMuted)
            }
            .frame(height: 29, alignment: .leading)

            meter(for: limit)
                .padding(.top, 6)
                .padding(.bottom, 7)

            Text(resetText(for: limit))
                .font(.system(size: 10))
                .foregroundStyle(Color.inkMuted)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(height: 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: limit.percent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(limit.shortTitle)
        .accessibilityValue("\(limit.percent) percent, \(resetText(for: limit))")
    }

    private func resetText(for limit: UsageLimit) -> String {
        let countdown = limit.countdown()
        guard !countdown.isEmpty else { return countdown }
        if countdown.lowercased().hasPrefix("reset") {
            return countdown
        }
        return "Resets in \(countdown)"
    }

    private func meter(for limit: UsageLimit) -> some View {
        GeometryReader { proxy in
            let fraction = min(1, max(0, Double(limit.percent) / 100))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.13))
                Capsule()
                    .fill(Color(hex: 0xD3D7DF))
                    .frame(width: proxy.size.width * CGFloat(fraction))
                    .overlay(alignment: .top) {
                        Color.white.opacity(0.4)
                            .frame(height: 1)
                    }
                    .clipShape(Capsule())
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }

    private var accessibilitySummary: String {
        var parts = monitor.limits.map {
            "\($0.shortTitle) \($0.percent) percent, \(resetText(for: $0))"
        }
        if monitor.isStale { parts.append("Cached") }
        if let error = monitor.error { parts.append(error) }
        return parts.joined(separator: ", ")
    }
}