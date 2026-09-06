import AppKit
import SwiftUI

struct UsageStrip: View {
    let monitor: LimitsMonitor

    @State private var isHovered = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                caption

                HStack(alignment: .top, spacing: 12) {
                    ForEach(monitor.limits) { limit in
                        column(for: limit)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered ? Color.panelHover : Color.panelGround)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.13), value: isHovered)
        .help("Open usage settings")
    }

    private var caption: some View {
        HStack(spacing: 6) {
            Text("Usage")
                .font(.sectionLabel)
                .foregroundStyle(Color.inkMuted)

            Spacer(minLength: 4)

            // Cached values remain useful, but must not masquerade as a fresh
            // reading when a fetch fails.
            if let error = monitor.error {
                HStack(spacing: 3) {
                    Image(systemName: monitor.isStale ? "clock" : "exclamationmark.triangle")
                    Text(monitor.isStale ? "cached" : error)
                }
                .font(.statFoot)
                .foregroundStyle(monitor.isStale ? Color.inkMuted : Color.alert)
                .lineLimit(1)
                .help(error)
            } else if monitor.isStale {
                Text("cached")
                    .font(.statFoot)
                    .foregroundStyle(Color.inkMuted)
            }

            if let model = monitor.model {
                Text(model)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.inkMuted)
                    .lineLimit(1)
            }

            Image(systemName: "arrow.up.right")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(Color.inkFaint)
                .accessibilityHidden(true)
        }
        .frame(height: 12)
    }

    private func column(for limit: UsageLimit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(limit.shortTitle)
                .font(.statLabel)
                .foregroundStyle(Color.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(height: 11)

            Text("\(limit.percent)%")
                .font(.statValue)
                .foregroundStyle(Color.ink)
                .contentTransition(.numericText())
                .frame(height: 22)

            meter(for: limit)

            Text(limit.countdown())
                .font(.statFoot)
                .foregroundStyle(Color.inkMuted)
                .monospacedDigit()
                .lineLimit(1)
                .frame(height: 11)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy(duration: 0.35), value: limit.percent)
        .accessibilityElement(children: .combine)
    }

    private func meter(for limit: UsageLimit) -> some View {
        GeometryReader { proxy in
            let fraction = min(1, max(0, Double(limit.percent) / 100))

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.panelRule)

                // Length and the printed percentage carry usage; the accent
                // does not introduce a separate, hue-only warning threshold.
                Rectangle()
                    .fill(Color.terracotta)
                    .frame(width: proxy.size.width * CGFloat(fraction))

                Rectangle()
                    .fill(Color.inkMuted)
                    .frame(width: 1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}
