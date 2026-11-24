import Foundation

/// The app binary doubles as a small command line, so a hotkey tool can hand
/// Perch a message without a URL scheme a web page could also open:
///
///     Perch send [--to NAME] [TEXT...]   text from the arguments, else stdin
///     Perch target [NAME]                print, or set, the chosen target
///     Perch targets                      list them, the chosen one marked
///
/// Exit 0 sent or done, 1 not sent, 2 a usage or setup problem. Runs before
/// AppKit starts and exits; the running app hears about it through
/// distributed notifications.
enum PerchCommand {
    static let verbs: Set<String> = ["send", "target", "targets"]

    /// nil when the arguments are not a command, and the app should start.
    static func run(_ arguments: [String]) -> Int32? {
        guard arguments.count > 1, verbs.contains(arguments[1]) else { return nil }
        let rest = Array(arguments.dropFirst(2))
        switch arguments[1] {
        case "send": return send(rest)
        case "target": return target(rest)
        default: return list()
        }
    }

    private static func loadOrSay() -> [MessageTarget]? {
        do { return try MessageTargets.load() } catch {
            let why = (error as? MessageTargets.TargetsError)?.description ?? error.localizedDescription
            fail("\(why) (\(MessageTargets.fileURL.path))")
            return nil
        }
    }

    private static func send(_ arguments: [String]) -> Int32 {
        var words = arguments
        var named: String?
        if let at = words.firstIndex(of: "--to") {
            guard words.indices.contains(at + 1) else { fail("--to needs a target name"); return 2 }
            named = words[at + 1]
            words.removeSubrange(at...(at + 1))
        }
        let raw = words.isEmpty
            ? String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
            : words.joined(separator: " ")
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { fail("nothing to send"); return 2 }

        guard let list = loadOrSay() else { return 2 }
        let name = named.flatMap { want in list.first { $0.name.caseInsensitiveCompare(want) == .orderedSame }?.name }
            ?? (named == nil ? MessageTargets.resolve(stored: MessageTargets.storedSelection(), in: list) : nil)
        guard let name, let target = list.first(where: { $0.name == name }) else {
            fail("no target named \(named ?? "?")")
            return 2
        }

        let result = MessageTargets.deliver(text, to: target)
        MessageTargets.announce(result)
        if result.ok {
            print(result.headline)
            return 0
        }
        fail("\(result.headline): \(result.detail)")
        return 1
    }

    private static func target(_ arguments: [String]) -> Int32 {
        guard let list = loadOrSay() else { return 2 }
        guard let want = arguments.first else {
            print(MessageTargets.resolve(stored: MessageTargets.storedSelection(), in: list) ?? "")
            return 0
        }
        guard let hit = list.first(where: { $0.name.caseInsensitiveCompare(want) == .orderedSame }) else {
            fail("no target named \(want); have \(list.map(\.name).joined(separator: ", "))")
            return 2
        }
        MessageTargets.store(selection: hit.name)
        print(hit.name)
        return 0
    }

    private static func list() -> Int32 {
        guard let list = loadOrSay() else { return 2 }
        let chosen = MessageTargets.resolve(stored: MessageTargets.storedSelection(), in: list)
        for target in list { print("\(target.name == chosen ? "*" : " ") \(target.name)") }
        return 0
    }

    private static func fail(_ message: String) {
        FileHandle.standardError.write(Data("perch: \(message)\n".utf8))
    }
}
