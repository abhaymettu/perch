import Foundation
import SwiftUI

/// One rate-limit window: the session block, the weekly account total, or a
/// weekly window scoped to a single model.
struct UsageLimit: Identifiable, Equatable {
    let kind: String
    let percent: Int
    let severity: String
    let resetsAt: Date?
    let modelName: String?

    var id: String { modelName.map { "\(kind):\($0)" } ?? kind }

    /// Every column names a window. Dropping to the bare model name gave the
    /// strip "SESSION / WEEKLY / FABLE" — two windows and a model, read as
    /// three of the same kind of thing.
    var shortTitle: String {
        guard kind.hasPrefix("weekly") else { return kind.uppercased() }
        return modelName.map { "WEEK · \($0.uppercased())" } ?? "WEEK · ALL"
    }

    /// The meter fill. Brand colour while there is nothing to worry about.
    var color: Color {
        switch severity {
        case "critical": .alert
        case "warning":  .warn
        default:         .accent
        }
    }

    /// The percentage itself stays plain until it means something. Three orange
    /// numbers stacked up read as three warnings when none of them is one.
    var valueColor: Color {
        severity == "normal" ? .ink : color
    }

    /// One token — "2h" — for the strip column and for the menu bar, both of
    /// which have room for exactly that beside the percentage.
    func countdown() -> String {
        guard let resetsAt else { return "" }

        let minutes = Int(resetsAt.timeIntervalSinceNow) / 60
        switch minutes {
        case ..<1:    return "now"
        case ..<60:   return "\(minutes)m"
        case ..<1440: return "\(minutes / 60)h"
        default:      return "\(minutes / 1440)d"
        }
    }
}

/// Reads Anthropic's OAuth usage endpoint — percent of limit per window, which
/// is the "am I about to be cut off" number. Dollars spent cannot answer that.
///
/// The token is read from the Keychain on every fetch and never written to disk
/// or logged.
@Observable
final class LimitsMonitor {

    private(set) var limits: [UsageLimit] = []
    private(set) var model: String?
    private(set) var error: String?

    /// Set when a fetch failed but earlier numbers are still on screen. The
    /// panel keeps showing them rather than blanking out.
    private(set) var isStale = false

    /// The endpoint drops persistently-429ing callers into a punitive bucket.
    /// 180s is the documented-safe floor; countdowns tick off `resetsAt`
    /// locally, so a slower poll costs nothing on screen.
    private static let interval: TimeInterval = 180
    private static let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private var timer: Timer?
    private var userAgent: String?

    init() {
        Task { await refresh() }

        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    deinit { timer?.invalidate() }

    #if DEBUG
    /// Seeded and inert, for the preview harness. Real data on this machine is
    /// all `normal`, so warning and critical would otherwise ship unrendered.
    init(frozen limits: [UsageLimit], model: String? = "opus-5", error: String? = nil) {
        self.limits = limits
        self.model = model
        self.error = error
    }
    #endif

    // MARK: - Fetch

    func refresh() async {
        do {
            let parsed = try Self.parse(await fetch())
            let settingsModel = Self.configuredModel()
            await MainActor.run {
                self.limits = parsed
                self.model = settingsModel
                self.error = nil
                self.isStale = false
            }
        } catch {
            let reason = (error as? UsageError)?.hint ?? "Usage API unreachable"
            await MainActor.run {
                self.error = reason
                self.isStale = !self.limits.isEmpty
            }
        }
    }

    enum UsageError: Error {
        case keychain, expired, http(Int)

        var hint: String {
            switch self {
            case .keychain:    "Keychain access denied"
            case .expired:     "Session expired — run /login"
            case .http(let c): "Usage API returned \(c)"
            }
        }
    }

    private func fetch() async throws -> Data {
        var request = URLRequest(url: Self.url, timeoutInterval: 20)
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        // A generic User-Agent lands this endpoint in a punitive rate-limit
        // bucket that returns persistent 429s.
        request.setValue("claude-code/\(await version())", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw UsageError.http(status) }
        return data
    }

    /// Shells out to `security` rather than calling `SecItemCopyMatching`: the
    /// Keychain ACL on this item is granted to that binary already, and Blink's
    /// own signature changes on every rebuild.
    private func token() async throws -> String {
        guard let output = await Shell.run(
            "/usr/bin/security",
            arguments: ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        ),
        let data = output.data(using: .utf8),
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let oauth = root["claudeAiOauth"] as? [String: Any],
        let accessToken = oauth["accessToken"] as? String else { throw UsageError.keychain }

        // expiresAt is milliseconds since the epoch, not seconds.
        let expiresAt = (oauth["expiresAt"] as? Double ?? 0) / 1000
        guard expiresAt > Date().timeIntervalSince1970 else { throw UsageError.expired }

        return accessToken
    }

    private func version() async -> String {
        if let userAgent { return userAgent }

        let paths = [
            ("~/.local/bin/claude" as NSString).expandingTildeInPath,
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude"
        ]
        var found: String?
        if let executable = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            found = await Shell.run(executable, arguments: ["--version"])?
                .split(separator: " ").first.map(String.init)
        }

        let resolved = found ?? "2.1.0"
        userAgent = resolved
        return resolved
    }

    // MARK: - Parsing

    /// The payload also carries a dozen null-valued codename windows
    /// (`nimbus_quill`, `tangelo`, …). `limits` is the normalised view of all
    /// of them and the only thing worth decoding.
    static func parse(_ data: Data) throws -> [UsageLimit] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = root["limits"] as? [[String: Any]] else { throw UsageError.http(0) }

        return raw.compactMap { entry -> UsageLimit? in
            guard let kind = entry["kind"] as? String,
                  let percent = entry["percent"] as? Int else { return nil }

            // A scoped weekly window at 0% is a model he is not using.
            guard kind != "weekly_scoped" || percent > 0 else { return nil }

            let model = (entry["scope"] as? [String: Any])?["model"] as? [String: Any]

            return UsageLimit(
                kind: kind,
                percent: min(max(percent, 0), 100),
                severity: entry["severity"] as? String ?? "normal",
                resetsAt: (entry["resets_at"] as? String).flatMap(ISO8601DateFormatter.usage.date(from:)),
                modelName: model?["display_name"] as? String
            )
        }
    }

    private static func configuredModel() -> String? {
        let path = ("~/.claude/settings.json" as NSString).expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: path),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return root["model"] as? String
    }

    // MARK: - Menu bar

    /// The session window leads, since that is what you are spending against
    /// right now. A longer window only takes over once it is close enough to
    /// actually stop you.
    var lead: UsageLimit? {
        let session = limits.first { $0.kind == "session" }
        let urgent = limits.filter { $0.id != session?.id && $0.percent >= 75 }

        if let hottest = urgent.max(by: { $0.percent < $1.percent }),
           hottest.percent > (session?.percent ?? -1) {
            return hottest
        }
        return session ?? limits.max { $0.percent < $1.percent }
    }

    /// " 4% · W 44%", and the reset countdown too once the lead is hot enough
    /// that knowing when it clears changes what you do next.
    var menuBarTitle: String {
        guard let lead else { return "" }

        var title = " \(lead.percent)%"
        if lead.severity != "normal" {
            title += " \(lead.countdown())"
        }
        if let weekly = limits.first(where: { $0.kind == "weekly_all" && $0.id != lead.id }) {
            title += " · W \(weekly.percent)%"
        }
        return title
    }

    #if DEBUG
    /// Pins lead selection and the scoped-window filter — the two rules that
    /// decide what the menu bar says.
    static func selfCheck() {
        let payload = """
        {"limits":[
          {"kind":"session","percent":4,"severity":"normal","resets_at":"2026-08-31T09:00:00.000000+00:00","scope":null},
          {"kind":"weekly_all","percent":44,"severity":"normal","resets_at":null,"scope":null},
          {"kind":"weekly_scoped","percent":41,"severity":"normal","resets_at":null,"scope":{"model":{"display_name":"Fable"}}},
          {"kind":"weekly_scoped","percent":0,"severity":"normal","resets_at":null,"scope":{"model":{"display_name":"Opus"}}}
        ]}
        """
        let parsed = try! parse(Data(payload.utf8))
        assert(parsed.count == 3, "0% scoped window was not dropped: \(parsed.count)")
        assert(parsed[0].resetsAt != nil, "fractional-second resets_at failed to decode")
        assert(parsed[2].shortTitle == "WEEK · FABLE", "got \(parsed[2].shortTitle)")

        let monitor = LimitsMonitor()
        monitor.timer?.invalidate()

        monitor.limits = parsed
        assert(monitor.lead?.kind == "session", "session should lead below 75%")
        assert(monitor.menuBarTitle == " 4% · W 44%", "got '\(monitor.menuBarTitle)'")

        // A weekly window past 75% and above the session takes the lead, and a
        // lead that is no longer "normal" carries its countdown.
        let inTwoHours = Date().addingTimeInterval(2 * 3600 + 60)
        monitor.limits[1] = UsageLimit(kind: "weekly_all", percent: 91, severity: "critical", resetsAt: inTwoHours, modelName: nil)
        assert(monitor.lead?.kind == "weekly_all", "hot weekly did not take the lead")
        assert(monitor.menuBarTitle == " 91% 2h", "got '\(monitor.menuBarTitle)'")
    }
    #endif
}

extension ISO8601DateFormatter {
    // resets_at carries fractional seconds; the default formatter rejects them.
    static let usage: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
