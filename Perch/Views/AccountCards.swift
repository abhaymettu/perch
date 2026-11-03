import SwiftUI

/// One section per Claude account when perch-usage polls more than one. Each
/// carries its own windows on its own clocks; nothing is summed across them.
/// Clicking a section makes it the account the menu bar title follows.
struct AccountCards: View {
    let monitor: LimitsMonitor
    let now: Date

    var body: some View {
        VStack(spacing: 2) {
            ForEach(monitor.accounts) { account in
                let drives = account.id == monitor.menuBarAccountID
                Button { monitor.chooseMenuBarAccount(account.id) } label: {
                    AccountSection(account: account, drivesMenuBar: drives, now: now)
                }
                .buttonStyle(PanelRowButtonStyle())
                .help(drives ? "Shown in the menu bar" : "Show in the menu bar")
                .accessibilityAddTraits(drives ? .isSelected : [])
                .accessibilityHint("Shows this account in the menu bar")
            }
        }
    }
}

private struct AccountSection: View {
    let account: AccountUsage
    let drivesMenuBar: Bool
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            // A signed-out account collapses to its header: its numbers are
            // history and the header already says why.
            if !account.isSignedOut {
                if let week = account.window("weekly_all") {
                    WeekBlock(limit: week, now: now, muted: account.status != "live")
                        .padding(.top, 9)
                }
                ForEach(account.windows.filter { $0.modelName != nil }) { model in
                    ModelLine(limit: model, now: now, muted: account.status != "live")
                        .padding(.top, 8)
                }
                if account.windows.isEmpty {
                    Text(account.reason ?? "No numbers yet")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.inkMuted)
                        .lineLimit(2)
                        .padding(.top, 6)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            MenuBarMark(on: drivesMenuBar)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }

            Text(account.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(account.isSignedOut ? Color.inkMuted : Color.ink)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)

            if let plan = account.plan {
                Text(plan)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.inkFaint)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let state = trailingState {
                HStack(spacing: 4) {
                    Image(systemName: state.symbol)
                        .font(.system(size: 10, weight: .medium))
                        .accessibilityHidden(true)
                    Text(state.word)
                }
                .font(.system(size: 11))
                .foregroundStyle(state.loud ? Color.alert : Color.inkMuted)
                .lineLimit(1)
                .fixedSize()
            } else if drivesMenuBar {
                Text("In menu bar")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.inkFaint)
                    .fixedSize()
            }
        }
    }

    /// The quiet state says nothing; anything else names what is wrong, in
    /// words and a symbol, never colour alone.
    private var trailingState: (word: String, symbol: String, loud: Bool)? {
        switch account.status {
        case "removed-needs-reauth": return ("Signed out", "person.crop.circle.badge.xmark", false)
        case "live", "cached":
            guard account.isStale(at: now) else { return nil }
            return ("Stale · \(age)", "clock", true)
        default: return ("Unavailable", "exclamationmark.triangle", true)
        }
    }

    private var age: String {
        guard let observedAt = account.observedAt else { return "never read" }
        let minutes = max(0, Int(now.timeIntervalSince(observedAt)) / 60)
        return switch minutes {
        case ..<60:   "\(minutes)m"
        case ..<1440: "\(minutes / 60)h"
        default:      "\(minutes / 1440)d"
        }
    }
}

/// Filled when this account titles the menu bar, an empty ring otherwise:
/// shape carries the meaning, so it reads without colour.
private struct MenuBarMark: View {
    let on: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.inkFaint.opacity(on ? 0 : 0.7), lineWidth: 1)
            if on {
                Circle().fill(Color.ink)
                Circle().fill(Color.panelBase).frame(width: 3, height: 3)
            }
        }
        .frame(width: 9, height: 9)
        .accessibilityHidden(true)
    }
}

/// The week at a glance: percent used, when it resets, and the meter.
struct WeekBlock: View {
    let limit: UsageLimit
    let now: Date
    var muted = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let passed = limit.hasReset(at: now)

        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                if passed {
                    Text("Week reset")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.inkMuted)
                } else {
                    Text("\(limit.percent)")
                        .font(.system(size: 22, weight: .semibold))
                        .tracking(-0.5)
                        .monospacedDigit()
                        .foregroundStyle(muted ? Color.inkMuted : Color.ink)
                        .contentTransition(.numericText(value: Double(limit.percent)))
                    Text("%")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.inkMuted)
                        .padding(.leading, 1)
                    Text(limit.percent >= 100 ? "  limit reached" : "  of week used")
                        .font(.system(size: 11, weight: limit.percent >= 100 ? .medium : .regular))
                        .foregroundStyle(limit.percent >= 100 && !muted ? Color.alert : Color.inkMuted)
                }

                Spacer(minLength: 8)

                Text(resetText(passed: passed))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(Color.inkMuted)
                    .lineLimit(1)
                    .help(limit.resetsAt.map { Self.exact.string(from: $0) } ?? "")
            }

            UsageMeter(fraction: passed ? 0 : Double(limit.percent) / 100,
                       fill: muted ? Color.inkFaint.opacity(0.6) : limit.meterColor, height: 5)
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: limit.percent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Week")
        .accessibilityValue(passed ? "reset" : "\(limit.percent) percent used, \(resetText(passed: false))")
    }

    private func resetText(passed: Bool) -> String {
        if passed { return "next reading soon" }
        let countdown = limit.countdown(from: now)
        return countdown.isEmpty ? "" : "resets in \(countdown)"
    }

    static let exact: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "'Resets' EEE MMM d, h:mm a"
        return formatter
    }()
}

/// A model's own week, one quiet line under the headline.
struct ModelLine: View {
    let limit: UsageLimit
    let now: Date
    var muted = false

    var body: some View {
        let passed = limit.hasReset(at: now)

        HStack(spacing: 8) {
            Text(limit.title)
                .font(.system(size: 11))
                .foregroundStyle(Color.inkMuted)
                .lineLimit(1)

            Spacer(minLength: 8)

            UsageMeter(fraction: passed ? 0 : Double(limit.percent) / 100,
                       fill: muted ? Color.inkFaint.opacity(0.6) : limit.meterColor, height: 3)
                .frame(width: 72)

            Text(passed ? "reset" : "\(limit.percent)%")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(muted ? Color.inkMuted : Color.ink)
                .frame(width: 34, alignment: .trailing)
        }
        .help(limit.resetsAt.map { WeekBlock.exact.string(from: $0) } ?? "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(limit.title)
        .accessibilityValue(passed ? "reset" : "\(limit.percent) percent used")
    }
}

struct UsageMeter: View {
    let fraction: Double
    let fill: Color
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.meterTrack)
                Capsule()
                    .fill(fill)
                    .frame(width: max(fraction > 0 ? height : 0, proxy.size.width * CGFloat(min(1, max(0, fraction)))))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

extension UsageLimit {
    /// Neutral until it matters; amber when the window is warning, critical or spent.
    var meterColor: Color {
        severity == "normal" && percent < 100 ? Color.meterFill : Color.alert
    }
}
