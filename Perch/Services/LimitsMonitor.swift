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

    /// Two units at most — "now", "14m", "2h 14m", "3d 5h" — for the strip
    /// column and for the menu bar. A zero small unit is dropped, so a reset
    /// exactly two hours out reads "2h", not "2h 0m".
    func countdown() -> String {
        guard let resetsAt else { return "" }

        // Rounded, because the interval is read a hair after it is computed and
        // truncation would turn 2h1m into 2h0m.
        let minutes = Int(resetsAt.timeIntervalSinceNow.rounded()) / 60
        func pair(_ big: Int, _ bigUnit: String, _ small: Int, _ smallUnit: String) -> String {
            small == 0 ? "\(big)\(bigUnit)" : "\(big)\(bigUnit) \(small)\(smallUnit)"
        }
        switch minutes {
        case ..<1:    return "now"
        case ..<60:   return "\(minutes)m"
        case ..<1440: return pair(minutes / 60, "h", minutes % 60, "m")
        default:      return pair(minutes / 1440, "d", minutes % 1440 / 60, "h")
        }
    }

    /// The window this number was observed in has already rolled over, so the
    /// number describes a window that no longer exists.
    var hasReset: Bool {
        resetsAt.map { $0 <= Date() } ?? false
    }
}

/// One Claude account's own windows, as the perch-usage LaunchAgent last saw
/// them. Accounts have separate limits on separate clocks, so nothing here is
/// ever added up or averaged across accounts.
struct AccountUsage: Identifiable, Equatable {
    let id: String
    let email: String?
    /// live | cached | unavailable | removed-needs-reauth
    let status: String
    let reason: String?
    let session: UsageLimit?
    let weekly: UsageLimit?
    let observedAt: Date?
    let lanes: [String]
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

    /// Every account perch-usage polls, ordered by id, and which of them the
    /// numbers above belong to. Empty when its state file is missing or garbled.
    private(set) var accounts: [AccountUsage] = []
    private(set) var account: String?

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
    /// Seeded and inert, for the preview harness. Real data is `normal` almost
    /// all the time, so warning and critical would otherwise ship unrendered.
    init(frozen limits: [UsageLimit], model: String? = "opus-5", error: String? = nil,
         accounts: [AccountUsage] = [], account: String? = nil) {
        self.limits = limits
        self.model = model
        self.error = error
        self.accounts = accounts
        self.account = account
    }
    #endif

    // MARK: - Fetch

    func refresh() async {
        // A local file, so it updates even when the fetch below fails.
        let (owner, accounts) = Self.readAccounts()
        await MainActor.run {
            self.account = owner
            self.accounts = accounts
        }

        do {
            let parsed = try Self.parse(await fetch())
            let settingsModel = Self.configuredModel()
            Self.publish(parsed)
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
    /// Keychain ACL on this item is granted to that binary already, and Perch's
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

    // MARK: - Widget feed

    /// Mirrors each successful fetch into Scriptable's iCloud folder, where the
    /// companion iOS widget (`Widget/Perch Usage.js`) reads it. Percentages and
    /// reset times only — never the token. A no-op unless Scriptable's folder
    /// already exists.
    private static let scriptableDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Mobile Documents/iCloud~dk~simonbs~Scriptable/Documents")

    private static func publish(_ limits: [UsageLimit]) {
        guard FileManager.default.fileExists(atPath: scriptableDirectory.path) else { return }

        let payload: [String: Any] = [
            "fetchedAt": Date().timeIntervalSince1970,
            "limits": limits.map { limit -> [String: Any] in
                [
                    "kind": limit.kind,
                    "percent": limit.percent,
                    "severity": limit.severity,
                    "resetsAt": limit.resetsAt.map(\.timeIntervalSince1970) ?? NSNull() as Any,
                    "model": limit.modelName ?? NSNull() as Any
                ]
            }
        ]

        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            try? data.write(to: scriptableDirectory.appending(path: "perch-usage.json"), options: .atomic)
        }
    }

    private static func configuredModel() -> String? {
        let path = ("~/.claude/settings.json" as NSString).expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: path),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return root["model"] as? String
    }

    // MARK: - Accounts

    /// Written every 300s by the perch-usage LaunchAgent, which polls each
    /// account with its own token. Perch only reads it: no extra token, no
    /// extra call against the endpoint's rate limit.
    private static let accountsPath = ("~/.local/state/perch-usage/state.json" as NSString).expandingTildeInPath

    static func readAccounts() -> (account: String?, accounts: [AccountUsage]) {
        FileManager.default.contents(atPath: accountsPath).map(parseAccounts) ?? (nil, [])
    }

    /// Missing or malformed pieces drop to nil rather than failing the file:
    /// an unavailable account has no windows at all, and that is a state to show.
    static func parseAccounts(_ data: Data) -> (account: String?, accounts: [AccountUsage]) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = root["accounts"] as? [String: [String: Any]] else { return (nil, []) }

        func window(_ kind: String, _ value: Any?) -> UsageLimit? {
            guard let value = value as? [String: Any],
                  let percent = value["usage_percent"] as? Int else { return nil }
            return UsageLimit(kind: kind, percent: min(max(percent, 0), 100), severity: "normal",
                              resetsAt: date(value["resets_at"]), modelName: nil)
        }

        let accounts = raw.keys.sorted().map { id in
            let entry = raw[id]!
            return AccountUsage(
                id: id,
                email: entry["email"] as? String,
                status: entry["status"] as? String ?? "unavailable",
                reason: entry["reason"] as? String,
                session: window("session", entry["session"]),
                weekly: window("weekly_all", entry["weekly"]),
                observedAt: date(entry["observed_at"]),
                lanes: entry["lanes"] as? [String] ?? []
            )
        }
        return (root["account"] as? String, accounts)
    }

    /// The writer emits timestamps both with and without fractional seconds.
    private static func date(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        return ISO8601DateFormatter.usage.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    // MARK: - Menu bar

    /// The session window always leads, since that is what you are spending
    /// against right now. A hot weekly window still shows, but as the trailing
    /// "· W nn%" rather than by taking over the bar.
    var lead: UsageLimit? {
        limits.first { $0.kind == "session" } ?? limits.max { $0.percent < $1.percent }
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

        // Frozen, not live: a live monitor's init reads the Keychain and calls
        // the endpoint before the timer can be stopped.
        let monitor = LimitsMonitor(frozen: [])

        monitor.limits = parsed
        assert(monitor.lead?.kind == "session", "session should lead below 75%")
        assert(monitor.menuBarTitle == " 4% · W 44%", "got '\(monitor.menuBarTitle)'")

        // The session keeps the lead even when another window is critical, and
        // a lead that is no longer "normal" carries its countdown.
        let inTwoHours = Date().addingTimeInterval(2 * 3600 + 60)
        monitor.limits[1] = UsageLimit(kind: "weekly_all", percent: 91, severity: "critical", resetsAt: inTwoHours, modelName: nil)
        assert(monitor.lead?.kind == "session", "session lost the lead to a hot weekly")
        assert(monitor.menuBarTitle == " 4% · W 91%", "got '\(monitor.menuBarTitle)'")

        monitor.limits[0] = UsageLimit(kind: "session", percent: 96, severity: "critical", resetsAt: inTwoHours, modelName: nil)
        assert(monitor.menuBarTitle == " 96% 2h 1m · W 91%", "got '\(monitor.menuBarTitle)'")

        // Both units, and the zero one dropped.
        let cases: [(TimeInterval, String)] = [
            (30, "now"), (840, "14m"), (8040, "2h 14m"), (7200, "2h"),
            (277_200, "3d 5h"), (259_200, "3d"),
        ]
        for (seconds, expected) in cases {
            let limit = UsageLimit(kind: "session", percent: 1, severity: "normal",
                                   resetsAt: Date().addingTimeInterval(seconds), modelName: nil)
            assert(limit.countdown() == expected, "\(seconds)s gave '\(limit.countdown())', want '\(expected)'")
        }

        // Accounts: ordered by id, both timestamp shapes decode, and a window
        // whose reset is behind us reads as reset, not as current usage.
        let state = """
        {"account":"acct2","accounts":{
          "acct2":{"status":"live","session":{"usage_percent":2,"resets_at":"2999-01-01T00:00:00+00:00"},
                   "weekly":{"usage_percent":0,"resets_at":null},"observed_at":"2026-10-09T15:25:50.1+00:00","lanes":["a","b"]},
          "acct1":{"status":"cached","session":{"usage_percent":4,"resets_at":"2020-01-01T00:00:00+00:00"},
                   "weekly":null,"observed_at":"2026-10-09T15:05:48+00:00","lanes":[]}}}
        """
        let (owner, accounts) = parseAccounts(Data(state.utf8))
        assert(owner == "acct2" && accounts.map(\.id) == ["acct1", "acct2"], "got \(accounts.map(\.id))")
        assert(accounts.allSatisfy { $0.observedAt != nil }, "observed_at failed to decode")
        assert(accounts[0].session?.hasReset == true, "a passed reset still reads as current")
        assert(accounts[1].session?.hasReset == false && accounts[1].weekly?.hasReset == false)
        assert(accounts[0].weekly == nil && accounts[1].lanes.count == 2)
        assert(parseAccounts(Data("garbage".utf8)).accounts.isEmpty)
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
