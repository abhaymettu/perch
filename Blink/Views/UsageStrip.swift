import SwiftUI

/// Percent of limit per window, which is the number that answers "am I about to
/// get cut off". One column per window: the three numbers are the largest text
/// in the panel because they are the only thing worth reading from a distance.
struct UsageStrip: View {
    let monitor: LimitsMonitor

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            caption

            HStack(alignment: .top, spacing: 10) {
                ForEach(monitor.limits) { limit in
                    column(for: limit)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .padding(.bottom, 12)
        .contentShape(Rectangle())
        .background(Color.white.opacity(isHovered ? 0.035 : 0))
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.13), value: isHovered)
        .onTapGesture {
            NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!)
        }
        .help("Open usage settings")
    }

    // MARK: - Caption

    private var caption: some View {
        HStack(spacing: 6) {
            Text("USAGE")
                .font(.sectionLabel)
                .tracking(1.1)
                .foregroundStyle(Color.inkFaint)

            Spacer(minLength: 4)

            // A failed fetch leaves the last good numbers on screen rather than
            // blanking the strip; the badge is what says they are not live.
            if let error = monitor.error {
                Text(monitor.isStale ? "cached" : error)
                    .font(.statFoot)
                    .foregroundStyle(monitor.isStale ? Color.inkFaint : Color.alert)
                    .lineLimit(1)
            }

            if let model = monitor.model {
                Text(model)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.inkMuted)
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.07), in: Capsule())
            }
        }
    }

    // MARK: - Column

    private func column(for limit: UsageLimit) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(limit.shortTitle)
                .font(.statLabel)
                .tracking(0.7)
                .foregroundStyle(Color.inkFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text("\(limit.percent)%")
                .font(.statValue)
                .foregroundStyle(limit.valueColor)
                .monospacedDigit()
                .contentTransition(.numericText())

            meter(for: limit)

            Text(limit.countdown())
                .font(.statFoot)
                .foregroundStyle(Color.inkFaint)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy(duration: 0.35), value: limit.percent)
    }

    private func meter(for limit: UsageLimit) -> some View {
        Capsule()
            .fill(Color.white.opacity(0.08))
            .frame(height: 3)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(limit.color)
                        // A window barely used still shows a sliver, so the
                        // column never reads as "no data".
                        .frame(width: max(3, proxy.size.width * Double(limit.percent) / 100))
                }
            }
            .clipShape(Capsule())
    }
}
