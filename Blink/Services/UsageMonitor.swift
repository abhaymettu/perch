import Foundation

struct UsageBlock: Equatable {
    let endsAt: Date
    let costUSD: Double
    let costPerHour: Double

    var remaining: TimeInterval { max(endsAt.timeIntervalSinceNow, 0) }

    /// "1h21m" — the menubar has room for one compact token beside the robot.
    var remainingLabel: String {
        let minutes = Int(remaining) / 60
        return minutes >= 60 ? "\(minutes / 60)h\(minutes % 60)m" : "\(minutes)m"
    }
}

/// Runs on its own timer. `ccusage blocks --active --json` was measured at
/// 4.1 seconds — riding the 3s poll would stall every refresh.
@Observable
final class UsageMonitor {
    private(set) var block: UsageBlock?

    private static let interval: TimeInterval = 60
    private static let searchPaths = [
        "/opt/homebrew/bin/ccusage",
        "/usr/local/bin/ccusage",
        ("~/.bun/bin/ccusage" as NSString).expandingTildeInPath
    ]

    private var timer: Timer?

    /// nil when ccusage is not installed — the strip hides entirely rather
    /// than showing an error nobody can act on from a menubar panel.
    private let executable = searchPaths.first {
        FileManager.default.isExecutableFile(atPath: $0)
    }

    init() {
        guard executable != nil else { return }
        Task { await refresh() }

        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    deinit { timer?.invalidate() }

    func refresh() async {
        guard let executable else { return }
        let output = await Shell.run(executable, arguments: ["blocks", "--active", "--json"])
        let parsed = output.flatMap { Self.parse($0) }

        await MainActor.run {
            if self.block != parsed { self.block = parsed }
        }
    }

    static func parse(_ json: String) -> UsageBlock? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocks = root["blocks"] as? [[String: Any]],
              let active = blocks.first,
              let endTime = active["endTime"] as? String,
              let endsAt = ISO8601DateFormatter.usage.date(from: endTime) else { return nil }

        return UsageBlock(
            endsAt: endsAt,
            costUSD: active["costUSD"] as? Double ?? 0,
            costPerHour: (active["burnRate"] as? [String: Any])?["costPerHour"] as? Double ?? 0
        )
    }
}

private extension ISO8601DateFormatter {
    // ccusage emits fractional seconds; the default formatter rejects them.
    static let usage: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
