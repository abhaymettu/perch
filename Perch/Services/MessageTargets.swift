import Foundation

/// One place a message can go: a name for the panel and a command that does
/// the sending. The command gets the message on stdin and says how it went by
/// its exit status, so anything that can send (a script, a CLI, an
/// `osascript` line) can be a target without Perch knowing what is behind it.
struct MessageTarget: Equatable, Decodable {
    let name: String
    /// The program and its arguments, run directly, never through a shell.
    /// A leading `~/` is expanded.
    let command: [String]
}

/// How one send went, as the panel and the menu bar say it.
struct SendResult: Equatable {
    let target: String
    let ok: Bool
    /// Empty when the send went through; otherwise why it did not, in one line.
    let detail: String
    let at: Date

    var headline: String { ok ? "Sent to \(target)" : "Not sent to \(target)" }
}

/// Message targets: where text from a send key goes. The list is the
/// person's own, in a file outside the app (`targets.json`, see `fileURL`),
/// because what a target runs is private to their machine. Which one is
/// chosen lives in Perch's defaults, so the panel's switch and `Perch target`
/// on the command line move the same thing.
///
/// Perch does not own a hotkey or a text box. A hotkey tool hands the text to
/// `Perch send` (see `PerchCommand`), which runs the chosen target's command.
/// The running app shows the result under the menu bar item.
@Observable
final class MessageTargets {
    private(set) var targets: [MessageTarget] = []
    /// The chosen target's name, resolved against the list: a stored name
    /// that is no longer listed falls back to the first target.
    private(set) var selected: String?
    /// Why the list could not be read, until it can.
    private(set) var problem: String?
    /// The last send any process reported, for the line under the switch.
    private(set) var lastResult: SendResult?

    private let frozen: Bool

    init() {
        frozen = false
        reload()
    }

    #if DEBUG
    /// For the preview harness: a fixed list, nothing read or written.
    init(frozen targets: [MessageTarget], selected: String?, lastResult: SendResult? = nil) {
        frozen = true
        self.targets = targets
        self.selected = selected
        self.lastResult = lastResult
    }
    #endif

    /// Rereads the file and the stored choice. Cheap: run when the panel opens
    /// and when another process says the choice moved.
    func reload() {
        guard !frozen else { return }
        do {
            let list = try Self.load()
            if list != targets { targets = list }
            if problem != nil { problem = nil }
        } catch {
            if !targets.isEmpty { targets = [] }
            let why = (error as? TargetsError)?.description ?? error.localizedDescription
            if problem != why { problem = why }
        }
        let now = Self.resolve(stored: Self.storedSelection(), in: targets)
        if now != selected { selected = now }
    }

    func select(_ name: String) {
        guard !frozen, name != selected, targets.contains(where: { $0.name == name }) else { return }
        selected = name
        Self.store(selection: name)
    }

    func record(_ result: SendResult) {
        lastResult = result
    }

    // MARK: - Shared with the command line (no UI state)

    static let defaultsKey = "messageTarget"
    /// Posted, with the new name, whenever the choice moves, so a hotkey tool
    /// can label its text box with where the text will go.
    static let targetChanged = Notification.Name("com.abhaymettu.perch.messageTargetChanged")
    /// Posted after every send with `target`, `ok` ("1" or "0") and `detail`.
    static let messageSent = Notification.Name("com.abhaymettu.perch.messageSent")

    /// `~/Library/Application Support/Perch/targets.json`, or `PERCH_TARGETS_FILE`.
    static var fileURL: URL {
        if let path = ProcessInfo.processInfo.environment["PERCH_TARGETS_FILE"], !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Perch/targets.json")
    }

    /// Where a message that could not be sent is kept, one file each.
    static var unsentDirectory: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("unsent", isDirectory: true)
    }

    enum TargetsError: Error, CustomStringConvertible {
        case missing
        case unreadable(String)
        case invalid(String)

        var description: String {
            switch self {
            case .missing: "No targets.json yet"
            case .unreadable(let why): "targets.json unreadable: \(why)"
            case .invalid(let why): "targets.json: \(why)"
            }
        }
    }

    /// The list from disk. A missing file is `.missing`, so the panel can
    /// stay quiet for everyone who never set this up.
    static func load(from url: URL = fileURL) throws -> [MessageTarget] {
        guard FileManager.default.fileExists(atPath: url.path) else { throw TargetsError.missing }
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw TargetsError.unreadable(error.localizedDescription) }
        return try parse(data)
    }

    /// `{"targets": [...]}` or a bare array of `{"name", "command"}`.
    static func parse(_ data: Data) throws -> [MessageTarget] {
        struct Wrapped: Decodable { let targets: [MessageTarget] }
        let decoder = JSONDecoder()
        let list: [MessageTarget]
        if let wrapped = try? decoder.decode(Wrapped.self, from: data) {
            list = wrapped.targets
        } else if let bare = try? decoder.decode([MessageTarget].self, from: data) {
            list = bare
        } else {
            throw TargetsError.invalid("expected {\"targets\": [{\"name\", \"command\"}]}")
        }
        var seen = Set<String>()
        for target in list {
            let name = target.name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { throw TargetsError.invalid("a target has no name") }
            guard let program = target.command.first, !program.isEmpty else {
                throw TargetsError.invalid("\(name) has no command")
            }
            guard seen.insert(name.lowercased()).inserted else { throw TargetsError.invalid("\(name) is listed twice") }
        }
        return list
    }

    static func resolve(stored: String?, in list: [MessageTarget]) -> String? {
        if let stored, let hit = list.first(where: { $0.name.caseInsensitiveCompare(stored) == .orderedSame }) {
            return hit.name
        }
        return list.first?.name
    }

    /// Read fresh from the preferences daemon: the command line and the app
    /// are separate processes writing the same key.
    static func storedSelection() -> String? {
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
        return UserDefaults.standard.string(forKey: defaultsKey)
    }

    static func store(selection name: String) {
        UserDefaults.standard.set(name, forKey: defaultsKey)
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
        DistributedNotificationCenter.default().postNotificationName(
            targetChanged, object: nil, userInfo: ["target": name], deliverImmediately: true
        )
    }

    static func announce(_ result: SendResult) {
        DistributedNotificationCenter.default().postNotificationName(
            messageSent, object: nil,
            userInfo: ["target": result.target, "ok": result.ok ? "1" : "0", "detail": result.detail],
            deliverImmediately: true
        )
    }

    /// Runs the target's command with the text on stdin and waits for it.
    /// Exit 0 is sent; anything else, a missing program or the timeout is not,
    /// and the text is kept in `unsentDirectory` so it is never lost.
    /// Blocks the calling thread: the command line calls it, never the UI.
    static func deliver(_ text: String, to target: MessageTarget, timeout: TimeInterval = 60,
                        keepUnsentIn unsent: URL? = unsentDirectory) -> SendResult {
        var detail = run(target, text: text, timeout: timeout)
        if let why = detail, let unsent {
            if let kept = keep(text, in: unsent) { detail = "\(why). Kept in \(kept.lastPathComponent)" }
        }
        return SendResult(target: target.name, ok: detail == nil, detail: detail ?? "", at: Date())
    }

    /// nil when the command exited 0, else why not.
    private static func run(_ target: MessageTarget, text: String, timeout: TimeInterval) -> String? {
        let argv = target.command.map { $0.hasPrefix("~/") ? ($0 as NSString).expandingTildeInPath : $0 }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: argv[0])
        process.arguments = Array(argv.dropFirst())
        var env = ProcessInfo.processInfo.environment
        // A hotkey tool's children often get launchd's bare PATH; a script's
        // `#!/usr/bin/env python3` should still find the usual installs.
        env["PATH"] = ([env["PATH"]] + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"])
            .compactMap { $0 }.joined(separator: ":")
        env["PERCH_TARGET"] = target.name
        process.environment = env

        guard FileManager.default.isExecutableFile(atPath: argv[0]) else { return "\(argv[0]) is not an executable" }

        // stderr goes to a file, not a pipe: a command that leaves a child
        // running with the pipe open would hold a pipe read open forever.
        let errorsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("perch-send-\(UUID().uuidString).err")
        guard FileManager.default.createFile(atPath: errorsURL.path, contents: nil),
              let errors = try? FileHandle(forWritingTo: errorsURL) else { return "could not make a scratch file" }
        defer { try? FileManager.default.removeItem(at: errorsURL) }

        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors

        do { try process.run() } catch { return "could not start \(argv[0]): \(error.localizedDescription)" }
        try? errors.close()

        // Armed before the write: a command that never reads a long message
        // would otherwise block the write past any timeout.
        let lock = NSLock()
        var timedOut = false
        let watchdog = DispatchWorkItem {
            if process.isRunning { lock.withLock { timedOut = true }; process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

        // A command that exits without reading stdin closes the pipe; writing
        // then raises SIGPIPE unless it is ignored.
        signal(SIGPIPE, SIG_IGN)
        try? input.fileHandleForWriting.write(contentsOf: Data(text.utf8))
        try? input.fileHandleForWriting.close()

        process.waitUntilExit()
        watchdog.cancel()

        if lock.withLock({ timedOut }) { return "timed out after \(Int(timeout)) s" }
        guard process.terminationStatus != 0 else { return nil }
        let stderr = (try? Data(contentsOf: errorsURL)) ?? Data()
        let last = String(decoding: stderr, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
        return String((last ?? "exit \(process.terminationStatus)").prefix(160))
    }

    private static func keep(_ text: String, in directory: URL) -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let url = directory.appendingPathComponent(formatter.string(from: Date()) + ".txt")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data((text + "\n").utf8).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    #if DEBUG
    /// The store and the send path against stand-in commands in a scratch
    /// folder. Never touches the real targets file or the stored choice.
    static func selfCheck() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("perch-targets-check-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Both file shapes parse; bad lists are refused with a reason.
        let wrapped = #"{"targets":[{"name":"A","command":["/bin/cat"]},{"name":"B","command":["/bin/cat"]}]}"#
        assert((try? parse(Data(wrapped.utf8)))?.map(\.name) == ["A", "B"], "wrapped list did not parse")
        assert((try? parse(Data(#"[{"name":"A","command":["/bin/cat"]}]"#.utf8)))?.count == 1, "bare list did not parse")
        assert((try? parse(Data(#"[{"name":"A","command":[]}]"#.utf8))) == nil, "a target with no command was accepted")
        assert((try? parse(Data(#"[{"name":"A","command":["x"]},{"name":"a","command":["y"]}]"#.utf8))) == nil,
               "a duplicate name was accepted")
        assert((try? load(from: dir.appendingPathComponent("absent.json"))) == nil, "a missing file loaded")

        // A stored name that is gone falls back to the first; case is forgiven.
        let list = (try? parse(Data(wrapped.utf8))) ?? []
        assert(resolve(stored: "b", in: list) == "B", "stored choice not found case-insensitively")
        assert(resolve(stored: "gone", in: list) == "A", "a stale choice did not fall back to the first target")
        assert(resolve(stored: nil, in: []) == nil, "an empty list chose something")

        // Sent: the command gets the exact text on stdin.
        let out = dir.appendingPathComponent("out.txt")
        let text = "hello \"there\" $HOME `x`\nsecond line"
        let sink = MessageTarget(name: "Sink", command: ["/bin/sh", "-c", "cat > \"$1\"", "sh", out.path])
        let sent = deliver(text, to: sink, keepUnsentIn: dir.appendingPathComponent("unsent"))
        assert(sent.ok && sent.headline == "Sent to Sink", "stand-in send failed: \(sent.detail)")
        assert((try? String(contentsOf: out, encoding: .utf8)) == text, "the command did not get the exact text")

        // Not sent: the last stderr line is the reason, and the text is kept.
        let unsent = dir.appendingPathComponent("unsent")
        let failing = MessageTarget(name: "Down", command: ["/bin/sh", "-c", "cat >/dev/null; echo busy >&2; echo thread gone >&2; exit 3"])
        let failed = deliver("keep me", to: failing, keepUnsentIn: unsent)
        assert(!failed.ok && failed.detail.hasPrefix("thread gone. Kept in "), "failure reason wrong: \(failed.detail)")
        let kept = (try? FileManager.default.contentsOfDirectory(at: unsent, includingPropertiesForKeys: nil)) ?? []
        assert(kept.count == 1 && (try? String(contentsOf: kept[0], encoding: .utf8)) == "keep me\n", "unsent text not kept")

        // A missing program, and one that hangs, fail with a reason.
        let missing = deliver("x", to: MessageTarget(name: "M", command: ["/nonexistent/send"]), keepUnsentIn: nil)
        assert(!missing.ok && missing.detail.contains("not an executable"), "missing program: \(missing.detail)")
        let hung = deliver("x", to: MessageTarget(name: "H", command: ["/bin/sleep", "5"]), timeout: 0.5, keepUnsentIn: nil)
        assert(!hung.ok && hung.detail.hasPrefix("timed out"), "hung command: \(hung.detail)")
    }
    #endif
}
