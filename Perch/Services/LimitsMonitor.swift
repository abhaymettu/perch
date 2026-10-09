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
    func countdown(from now: Date = Date()) -> String {
        guard let resetsAt else { return "" }

        // Rounded, because the interval is read a hair after it is computed and
        // truncation would turn 2h1m into 2h0m.
        let minutes = Int(resetsAt.timeIntervalSince(now).rounded()) / 60
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

    /// The window this number was observed in has rolled over, so the number
    /// describes a window that no longer exists. `now` comes from the view's
    /// clock: a card drawn a minute before a reset must flip when the reset
    /// passes, not when the next poll happens to redraw it.
    func hasReset(at now: Date = Date()) -> Bool {
        resetsAt.map { $0 <= now } ?? false
    }
}

/// One Claude account's own windows, as the perch-usage LaunchAgent last saw
/// them. Accounts have separate limits on separate clocks, so nothing here is
/// ever added up or averaged across accounts.
struct AccountUsage: Identifiable, Equatable {
    let id: String
    /// His own name for the account, from accounts.json ("Main account").
    let label: String?
    let email: String?
    /// live | cached | unavailable | removed-needs-reauth
    let status: String
    let reason: String?
    let windows: [UsageLimit]
    let observedAt: Date?

    /// Signed out on this Mac: the numbers are history, kept for reference.
    var isSignedOut: Bool { status == "removed-needs-reauth" }

    /// The id is for data only; a registry without a label falls back to the email.
    var name: String { label ?? email ?? id }

    func window(_ kind: String) -> UsageLimit? { windows.first { $0.kind == kind } }

    /// Three missed polls: the same rule pocket-herdr and lane-ledger use.
    static let staleAfter: TimeInterval = 15 * 60

    /// Not fetched live within the last 15 minutes, so the numbers may have moved.
    func isStale(at now: Date) -> Bool {
        status != "live" || observedAt.map { now.timeIntervalSince($0) > Self.staleAfter } ?? true
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

    /// Every account perch-usage polls, signed-in first, and which of them the
    /// menu bar numbers belong to. Empty when its state file is missing.
    private(set) var accounts: [AccountUsage] = []
    private(set) var account: String?

    /// The account the menu bar title follows, as he chose it in the panel.
    /// nil follows perch-usage's default account.
    private(set) var menuBarAccount: String? = UserDefaults.standard.string(forKey: LimitsMonitor.menuBarAccountKey)
    private static let menuBarAccountKey = "menuBarAccount"
    @ObservationIgnored private var accountsStamp: Date?

    /// The endpoint drops persistently-429ing callers into a punitive bucket.
    /// 180s is the documented-safe floor; countdowns tick off `resetsAt`
    /// locally, so a slower poll costs nothing on screen.
    private static let interval: TimeInterval = 180
    private static let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private var timer: Timer?
    private var userAgent: String?

    init() {
        reloadAccountsIfChanged()
        Task { await refresh() }

        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    deinit { timer?.invalidate() }

    #if DEBUG
    /// Seeded and inert, for the preview harness. Real data is `normal` almost
    /// all the time, so warning and critical would otherwise ship unrendered.
    init(frozen limits: [UsageLimit], model: String? = "opus-5", error: String? = nil, stale: Bool = false,
         accounts: [AccountUsage] = [], account: String? = nil, menuBarAccount: String? = nil) {
        self.accounts = accounts
        self.account = account
        self.menuBarAccount = menuBarAccount
        self.limits = limits
        self.isStale = stale
        self.model = model
        self.error = error
    }
    #endif

    // MARK: - Fetch

    func refresh() async {
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

    // MARK: - Menu bar

    /// The two windows this build shows: the session block and the weekly
    /// account total. Model-scoped weekly windows are left out.
    var headline: [UsageLimit] {
        limits.filter { $0.kind == "session" || $0.kind == "weekly_all" }
    }

    /// Awake while there is a live reading to watch; dozing before the first
    /// fetch and while the chosen account is signed out.
    var owlAwake: Bool {
        isMultiAccount ? selectedAccount?.status == "live" : !limits.isEmpty
    }

    /// Red owl: any window critical, or the numbers shown are failing to refresh.
    /// A signed-out account is a known state he chose to watch, not a failure.
    var owlAlert: Bool {
        guard isMultiAccount else { return error != nil || limits.contains { $0.severity == "critical" } }
        guard let picked = selectedAccount else { return true }
        return (!picked.isSignedOut && picked.isStale(at: Date())) || picked.windows.contains { $0.severity == "critical" }
    }

    var menuBarTitle: String { menuBarTitle(at: Date()) }

    /// With several accounts the title and that account's card read the same
    /// state.json row, so they can never disagree. The title is numbers only,
    /// whichever account is picked: which one it is lives in the panel's picker
    /// (his call, 2026-10-09 11:40). A chosen account that is missing, signed
    /// out or stale says so: never another account's numbers in its place.
    func menuBarTitle(at now: Date) -> String {
        guard isMultiAccount else { return fetchedTitle }
        guard let picked = selectedAccount else { return "Account not found" }
        if picked.isSignedOut { return "Signed out" }
        guard !picked.windows.isEmpty else { return "Usage unavailable" }

        func part(_ label: String, _ kind: String) -> String {
            guard let window = picked.window(kind) else { return "\(label) n/a" }
            return window.hasReset(at: now) ? "\(label) reset" : "\(label) \(window.percent)%"
        }
        return "\(part("S", "session")) · \(part("W", "weekly_all")) used"
            + (picked.isStale(at: now) ? " · stale" : "")
    }

    /// "S 4% · W 44% used". Percent used, never remaining. A window the payload
    /// lacks reads "n/a", and with no successful fetch yet it says so rather
    /// than guessing 0. "stale" is appended when the last fetch failed.
    private var fetchedTitle: String {
        guard !headline.isEmpty else { return error == nil ? "Usage …" : "Usage unavailable" }

        func part(_ label: String, _ kind: String) -> String {
            headline.first { $0.kind == kind }.map { "\(label) \($0.percent)%" } ?? "\(label) n/a"
        }
        return "\(part("S", "session")) · \(part("W", "weekly_all")) used" + (isStale ? " · stale" : "")
    }

    // MARK: - Accounts

    /// Written every 300 s by the perch-usage LaunchAgent, which polls each
    /// account with that account's own keychain item. Perch only reads it: no
    /// extra token, no extra call against the endpoint's rate limit.
    private static let accountsPath = ("~/.local/state/perch-usage/state.json" as NSString).expandingTildeInPath

    static func readAccounts() -> (account: String?, accounts: [AccountUsage]) {
        FileManager.default.contents(atPath: accountsPath).map(parseAccounts) ?? (nil, [])
    }

    /// Cards and the panel's picker take over once there is more than one account.
    var isMultiAccount: Bool { accounts.count > 1 }

    var menuBarAccountID: String? { menuBarAccount ?? account }

    var selectedAccount: AccountUsage? { accounts.first { $0.id == menuBarAccountID } }

    func chooseMenuBarAccount(_ id: String) {
        menuBarAccount = id
        UserDefaults.standard.set(id, forKey: Self.menuBarAccountKey)
    }

    /// Called every second: a stat, and a read only when the poller has written.
    /// A file that will not parse is skipped without recording its stamp, so it
    /// is read again next second rather than blanking the cards.
    func reloadAccountsIfChanged() {
        let stamp = (try? FileManager.default.attributesOfItem(atPath: Self.accountsPath))?[.modificationDate] as? Date
        guard stamp != accountsStamp else { return }
        let read = Self.readAccounts()
        guard stamp == nil || !read.accounts.isEmpty else { return }
        accountsStamp = stamp
        (account, accounts) = read
    }

    /// Missing or malformed pieces drop out rather than failing the file: an
    /// unavailable account has no windows at all, and that is a state to show.
    static func parseAccounts(_ data: Data) -> (account: String?, accounts: [AccountUsage]) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = root["accounts"] as? [String: [String: Any]] else { return (nil, []) }

        func window(_ kind: String, _ value: Any?, model: String? = nil) -> UsageLimit? {
            guard let value = value as? [String: Any],
                  let percent = value["usage_percent"] as? Int else { return nil }
            return UsageLimit(kind: kind, percent: min(max(percent, 0), 100),
                              severity: value["severity"] as? String ?? "normal",
                              resetsAt: date(value["resets_at"]), modelName: model)
        }

        let accounts = raw.map { id, entry in
            let fable = window("weekly_scoped", (entry["models"] as? [String: Any])?["fable"], model: "Fable")
            return AccountUsage(
                id: id,
                label: entry["label"] as? String,
                email: entry["email"] as? String,
                status: entry["status"] as? String ?? "unavailable",
                reason: entry["reason"] as? String,
                windows: [window("session", entry["session"]), window("weekly_all", entry["weekly"]), fable]
                    .compactMap { $0 },
                observedAt: date(entry["observed_at"])
            )
        }
        // Signed-in accounts first, then by id: the one you can spend leads.
        return (root["account"] as? String,
                accounts.sorted { ($0.isSignedOut ? 1 : 0, $0.id) < ($1.isSignedOut ? 1 : 0, $1.id) })
    }

    /// The writer emits timestamps both with and without fractional seconds.
    private static func date(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        return ISO8601DateFormatter.usage.date(from: string) ?? ISO8601DateFormatter().date(from: string)
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
        assert(monitor.headline.count == 2, "scoped window leaked into headline")
        assert(monitor.menuBarTitle == "S 4% · W 44% used", "got '\(monitor.menuBarTitle)'")

        monitor.limits = [parsed[1]]
        assert(monitor.menuBarTitle == "S n/a · W 44% used", "got '\(monitor.menuBarTitle)'")

        monitor.limits = []
        assert(monitor.menuBarTitle == "Usage …" || monitor.menuBarTitle == "Usage unavailable",
               "empty limits must not read as 0%: '\(monitor.menuBarTitle)'")

        let inTwoHours = Date().addingTimeInterval(2 * 3600 + 60)
        monitor.limits = [
            UsageLimit(kind: "session", percent: 96, severity: "critical", resetsAt: inTwoHours, modelName: nil),
            parsed[1],
        ]
        assert(monitor.menuBarTitle == "S 96% · W 44% used", "got '\(monitor.menuBarTitle)'")

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

        // Injected clock, the 2026-10-09 case: acct1's 5h window reset at 15:39Z
        // and a panel opened at 15:40Z still said "4% in 1m".
        let reset = ISO8601DateFormatter().date(from: "2026-10-09T15:39:00Z")!
        let expiring = UsageLimit(kind: "session", percent: 4, severity: "normal", resetsAt: reset, modelName: nil)
        assert(!expiring.hasReset(at: reset.addingTimeInterval(-60)) && expiring.countdown(from: reset.addingTimeInterval(-60)) == "1m")
        assert(expiring.hasReset(at: reset), "a reset at exactly now is passed")
        assert(expiring.hasReset(at: reset.addingTimeInterval(60)), "15:40Z still read as the 15:39Z window")

        // Accounts: signed-in first, both timestamp shapes, Fable kept, garbage empty.
        let state = """
        {"account":"acct2","accounts":{
          "acct1":{"status":"removed-needs-reauth","session":{"usage_percent":4,"resets_at":"2026-10-09T15:39:00+00:00"},
                   "weekly":{"usage_percent":99,"resets_at":"2026-10-09T23:00:00+00:00"},"observed_at":"2026-10-09T15:05:48+00:00"},
          "acct2":{"status":"live","session":{"usage_percent":8,"resets_at":"2026-10-09T19:59:00+00:00"},
                   "weekly":{"usage_percent":2,"resets_at":null},"models":{"fable":{"usage_percent":1,"resets_at":null}},
                   "observed_at":"2026-10-09T15:40:51.3+00:00"}}}
        """
        let (owner, accounts) = parseAccounts(Data(state.utf8))
        assert(owner == "acct2" && accounts.map(\.id) == ["acct2", "acct1"], "got \(accounts.map(\.id))")
        assert(accounts.allSatisfy { $0.observedAt != nil }, "observed_at failed to decode")
        assert(accounts[0].windows.map(\.shortTitle) == ["SESSION", "WEEK · ALL", "WEEK · FABLE"])
        assert(accounts[1].isSignedOut && accounts[1].windows.count == 2)
        assert(accounts[1].windows[0].hasReset(at: reset.addingTimeInterval(60)))
        assert(parseAccounts(Data("garbage".utf8)).accounts.isEmpty)

        // Title and card from one row; the chosen account is never swapped for another.
        let at = ISO8601DateFormatter().date(from: "2026-10-09T15:42:00Z")!
        let labelled = parseAccounts(Data(state.replacingOccurrences(of: "\"acct1\":{", with: "\"acct1\":{\"label\":\"Main account\",")
            .replacingOccurrences(of: "\"acct2\":{", with: "\"acct2\":{\"label\":\"Second account\",").utf8))
        let rows = LimitsMonitor(frozen: parsed, accounts: labelled.accounts, account: "acct2")
        assert(rows.menuBarTitle(at: at) == "S 8% · W 2% used", "got '\(rows.menuBarTitle(at: at))'")
        // The fixture's 15:40Z reading is long past 15 minutes on the real clock.
        assert(rows.selectedAccount?.name == "Second account" && rows.owlAlert, "a stale live row alarms")
        assert(rows.menuBarTitle(at: at.addingTimeInterval(16 * 60)) == "S 8% · W 2% used · stale")
        let main = LimitsMonitor(frozen: [], accounts: labelled.accounts, account: "acct2", menuBarAccount: "acct1")
        assert(main.menuBarTitle(at: at) == "Signed out", "got '\(main.menuBarTitle(at: at))'")
        assert(!main.owlAwake && !main.owlAlert, "a signed-out choice dozes, it does not alarm")
        let gone = LimitsMonitor(frozen: parsed, accounts: labelled.accounts, account: "acct2", menuBarAccount: "acct9")
        assert(gone.menuBarTitle(at: at) == "Account not found" && gone.owlAlert)

        // Binding: a picked live account shows its own numbers, unnamed, never the default's.
        let both = parseAccounts(Data(state.replacingOccurrences(of: "\"removed-needs-reauth\"", with: "\"live\"")
            .replacingOccurrences(of: "\"observed_at\":\"2026-10-09T15:05:48+00:00\"", with: "\"observed_at\":\"2026-10-09T15:40:51+00:00\"").utf8))
        let early = reset.addingTimeInterval(-120)
        let picked1 = LimitsMonitor(frozen: parsed, accounts: both.accounts, account: "acct2", menuBarAccount: "acct1")
        let picked2 = LimitsMonitor(frozen: parsed, accounts: both.accounts, account: "acct2", menuBarAccount: "acct2")
        assert(picked1.menuBarTitle(at: early) == "S 4% · W 99% used", "got '\(picked1.menuBarTitle(at: early))'")
        assert(picked2.menuBarTitle(at: early) == "S 8% · W 2% used", "got '\(picked2.menuBarTitle(at: early))'")
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
