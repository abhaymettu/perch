import SwiftUI

/// One card per Claude account when perch-usage polls more than one. Each card
/// carries its own windows on its own clocks; nothing is summed across cards.
struct AccountCards: View {
    let monitor: LimitsMonitor

    var body: some View {
        // The file changes every 300 s, but a window can roll over between
        // polls, and the observed age has to keep counting.
        TimelineView(.periodic(from: .now, by: 15)) { context in
            VStack(spacing: 8) {
                ForEach(monitor.accounts) { account in
                    AccountCard(account: account, drivesMenuBar: account.id == monitor.account, now: context.date)
                }
            }
        }
    }
}

private struct AccountCard: View {
    let account: AccountUsage
    let drivesMenuBar: Bool
    let now: Date

    /// Three missed polls: the same rule pocket-herdr and lane-ledger use.
    private static let staleAfter: TimeInterval = 15 * 60

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if account.windows.isEmpty {
                Text(account.reason ?? "No numbers yet")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.inkMuted)
                    .lineLimit(2)
                    .padding(.top, 10)
            } else {
                // Three fixed slots, so SESSION and WEEK line up from card to card
                // whether or not an account has a Fable window.
                HStack(alignment: .top, spacing: 13) {
                    ForEach(0..<3, id: \.self) { slot in
                        if slot < account.windows.count {
                            UsageColumn(limit: account.windows[slot], now: now, muted: account.status != "live")
                        } else {
                            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                        }
                    }
                }
                .padding(.top, 11)
            }

            PerchHairline()
                .padding(.top, 10)
                .padding(.bottom, 7)

            Text(observedText)
                .font(.system(size: 10))
                .foregroundStyle(isStale ? Color.alert : Color.inkMuted)
                .monospacedDigit()
                .lineLimit(1)
                .frame(height: 13)
        }
        .padding(.horizontal, 12)
        .padding(.top, 11)
        .padding(.bottom, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .perchGlassCard(radius: 11)
        .help(account.reason ?? "")
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(account.id)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(account.isSignedOut ? Color.inkMuted : Color.ink)

            if let name = account.email?.split(separator: "@").first {
                Text(name)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.inkMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)

            PerchStateLabel(word: status.word, state: status.mark)
                .fixedSize()
        }
        .frame(height: 17)
    }

    /// Signed in is the quiet state; everything else names what is wrong.
    private var status: (word: String, mark: PerchMark) {
        switch account.status {
        case "live":                 ("Active", .healthy)
        case "cached":               ("Cached", .working)
        case "removed-needs-reauth": ("Signed out on this Mac", .warning)
        default:                     ("Unavailable", .warning)
        }
    }

    private var isStale: Bool {
        account.status == "live" && account.observedAt.map { now.timeIntervalSince($0) > Self.staleAfter } ?? true
    }

    /// "Observed 10:45 · 3m ago · menu bar". Clock time today, date before that.
    private var observedText: String {
        guard let observedAt = account.observedAt else { return "Never observed" }
        let formatter = Calendar.current.isDateInToday(observedAt) ? Self.time : Self.dayTime
        let minutes = max(0, Int(now.timeIntervalSince(observedAt)) / 60)
        let age = switch minutes {
        case ..<1:    "just now"
        case ..<60:   "\(minutes)m ago"
        case ..<1440: "\(minutes / 60)h ago"
        default:      "\(minutes / 1440)d ago"
        }
        var parts = ["\(account.isSignedOut ? "Last observed" : "Observed") \(formatter.string(from: observedAt))", age]
        if isStale { parts.append("stale") }
        if drivesMenuBar { parts.append("menu bar") }
        return parts.joined(separator: " · ")
    }

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dayTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d HH:mm"
        return formatter
    }()
}

/// Title, percent, meter, reset: one window. A window whose reset has passed
/// shows a dash and an empty meter, never its old number as if it were current.
struct UsageColumn: View {
    let limit: UsageLimit
    var now = Date()
    var muted = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let passed = limit.hasReset(at: now)

        VStack(alignment: .leading, spacing: 0) {
            Text(limit.shortTitle)
                .font(.system(size: 11))
                .foregroundStyle(Color.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(height: 15)

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(passed ? "—" : "\(limit.percent)")
                    .font(.system(size: 23, weight: .medium))
                    .tracking(-0.55)
                    .foregroundStyle(passed || muted ? Color.inkMuted : limit.valueColor)
                    .monospacedDigit()
                    .contentTransition(.numericText())

                if !passed {
                    Text("%")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.inkMuted)
                }
            }
            .frame(height: 29, alignment: .leading)

            meter(fraction: passed ? 0 : Double(limit.percent) / 100)
                .padding(.top, 6)
                .padding(.bottom, 7)

            Text(resetText(passed: passed))
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
        .accessibilityValue(passed ? "reset passed" : "\(limit.percent) percent, \(resetText(passed: false))")
    }

    private func resetText(passed: Bool) -> String {
        if passed { return "Reset passed" }
        let countdown = limit.countdown(from: now)
        return countdown.isEmpty ? "" : "Resets in \(countdown)"
    }

    private func meter(fraction: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.13))
                Capsule()
                    .fill(Color(hex: 0xD3D7DF).opacity(muted ? 0.45 : 1))
                    .frame(width: proxy.size.width * CGFloat(min(1, max(0, fraction))))
                    .overlay(alignment: .top) {
                        Color.white.opacity(muted ? 0.15 : 0.4)
                            .frame(height: 1)
                    }
                    .clipShape(Capsule())
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}
