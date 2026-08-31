import Foundation

enum ClaudeScanner {

    // MARK: - Scan

    static func scan(includeDesktop: Bool) async -> [ClaudeSession] {
        guard let output = await Shell.run(
            "/bin/ps",
            arguments: ["-axo", "pid=,ppid=,args="]
        ) else { return [] }

        let processes = parse(output)
        let claudes = processes.compactMap { process -> Candidate? in
            guard let (kind, name) = classify(process.args) else { return nil }
            guard includeDesktop || kind != .desktop else { return nil }
            return Candidate(process: process, kind: kind, rawName: name)
        }

        return await assemble(claudes)
    }

    // MARK: - ps parsing

    struct RawProcess: Equatable, Sendable {
        let pid: Int
        let ppid: Int
        let args: String
    }

    static func parse(_ output: String) -> [RawProcess] {
        output.split(separator: "\n").compactMap { line in
            // maxSplits: 2 leaves the arguments — which contain spaces — whole.
            let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard fields.count == 3,
                  let pid = Int(fields[0]),
                  let ppid = Int(fields[1]) else { return nil }

            return RawProcess(pid: pid, ppid: ppid, args: String(fields[2]))
        }
    }

    // MARK: - Classification

    /// Returns nil for anything that is not a Claude process.
    ///
    /// Matching is on argv[0] alone, never on the whole argument string: every
    /// shell Claude spawns carries `~/.claude/shell-snapshots/...` in its
    /// arguments, and a substring match over those inflates the count roughly
    /// fifteenfold with processes that are not Claude at all.
    static func classify(_ args: String) -> (kind: SessionKind, name: String)? {
        let executable = String(args.split(separator: " ", maxSplits: 1).first ?? "")
        guard !executable.isEmpty else { return nil }

        if executable.hasPrefix("/Applications/Claude.app/") {
            return (.desktop, "Claude")
        }

        // The CLI runs either as `claude` or, once it re-execs, as the versioned
        // binary at ~/.local/share/claude/versions/<version>.
        let isCLI = (executable as NSString).lastPathComponent == "claude"
            || executable.contains("/claude/versions/")
        guard isCLI else { return nil }

        if args.contains("remote-control"), let lane = flagValue("--name", in: args) {
            return (.remoteControl, lane)
        }

        // Headless and interactive both get their name from the working
        // directory; argv carries nothing a human would recognise.
        if args.contains("--sdk-url") || args.contains("--print") {
            return (.headless, "")
        }

        return (.interactive, "")
    }

    static func flagValue(_ flag: String, in args: String) -> String? {
        let fields = args.split(separator: " ").map(String.init)
        guard let index = fields.firstIndex(of: flag), index + 1 < fields.count else { return nil }
        let value = fields[index + 1]
        return value.hasPrefix("-") ? nil : value
    }

    // MARK: - Assembly

    struct Candidate: Sendable {
        let process: RawProcess
        let kind: SessionKind
        let rawName: String
    }

    private static let maxAncestorHops = 8

    /// The outermost Claude process above this one, or nil if this is itself a
    /// root. Non-Claude processes in between (a shell, a wrapper) are walked
    /// through, not treated as a boundary.
    static func rootPID(of candidate: Candidate, among byPID: [Int: Candidate]) -> Int? {
        var root: Int?
        var pid = candidate.process.ppid

        for _ in 0..<maxAncestorHops {
            guard pid > 1 else { break }
            if byPID[pid] != nil { root = pid }
            guard let next = ProcessResolver.parentPID(of: pid) else { break }
            pid = next
        }

        return root
    }

    /// Collapses the process list into one row per session: a child Claude
    /// process (a lane's live session, a headless worker) folds into its
    /// outermost Claude ancestor rather than earning its own row.
    private static func assemble(_ candidates: [Candidate]) async -> [ClaudeSession] {
        let byPID = Dictionary(candidates.map { ($0.process.pid, $0) }) { first, _ in first }

        var descendants: [Int: [Candidate]] = [:]
        var roots: [Candidate] = []

        for candidate in candidates {
            if let root = rootPID(of: candidate, among: byPID) {
                descendants[root, default: []].append(candidate)
            } else {
                roots.append(candidate)
            }
        }

        return await withTaskGroup(of: ClaudeSession?.self) { group in
            for root in roots {
                let children = descendants[root.process.pid] ?? []
                group.addTask { await session(for: root, children: children) }
            }

            var results: [ClaudeSession] = []
            for await session in group {
                if let session { results.append(session) }
            }
            return results.sorted {
                $0.kind.sortOrder == $1.kind.sortOrder
                    ? $0.name < $1.name
                    : $0.kind.sortOrder < $1.kind.sortOrder
            }
        }
    }

    #if DEBUG
    /// Runs on every debug launch. Pins the one rule the whole scanner rests
    /// on: match argv[0], never the argument string. A `grep claude` over full
    /// args matched every shell Claude had ever spawned and reported 341
    /// processes where there were 25.
    static func selfCheck() {
        let fixture = """
        99748  1 /Users/abhay/.local/share/claude/versions/2.1.0/claude remote-control --name chief
        27253 99748 /Users/abhay/.local/share/claude/versions/2.1.0/claude --print --sdk-url https://x --session-id a1b2c3d4e5f6
        41002  1 claude
         3311  1 /Applications/Claude.app/Contents/MacOS/Claude
        88120 41002 /bin/zsh -c source /Users/abhay/.claude/shell-snapshots/snapshot-zsh-1.sh && npm test
        """

        let processes = parse(fixture)
        assert(processes.count == 5, "parse dropped lines: \(processes.count)")
        assert(processes[0].pid == 99748 && processes[0].ppid == 1)
        assert(processes[1].args.contains("--session-id"), "args truncated at first space")

        let kinds = processes.map { classify($0.args)?.kind }
        assert(kinds == [.remoteControl, .headless, .interactive, .desktop, nil], "got \(kinds)")

        assert(classify(processes[0].args)?.name == "chief")
        assert(classify(processes[1].args)?.name == "", "headless names come from cwd, not argv")
        assert(classify(processes[2].args)?.name == "", "interactive names come from cwd, not argv")

        // Grouping: the headless session under chief is not its own row.
        let candidates = processes.compactMap { process -> Candidate? in
            guard let (kind, name) = classify(process.args) else { return nil }
            return Candidate(process: process, kind: kind, rawName: name)
        }
        let byPID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.process.pid, $0) })
        assert(rootPID(of: candidates[1], among: byPID) == 99748, "headless child did not fold into its lane")
        assert(rootPID(of: candidates[0], among: byPID) == nil, "lane should be a root")
    }
    #endif

    private static func session(for root: Candidate, children: [Candidate]) async -> ClaudeSession? {
        let pid = root.process.pid
        guard let startedAt = ProcessResolver.startTime(of: pid) else { return nil }

        let directory = await ProcessResolver.workingDirectory(pid: pid)

        let name: String
        if root.rawName.isEmpty {
            name = directory.isEmpty
                ? "Session \(pid)"
                : ProcessResolver.resolveProjectName(from: directory)
        } else {
            name = root.rawName
        }

        // A lane's own uptime says nothing useful; what matters is how long the
        // session it is currently driving has been open.
        let activeSince = children
            .filter { $0.kind == .headless }
            .compactMap { ProcessResolver.startTime(of: $0.process.pid) }
            .min()

        return ClaudeSession(
            id: ClaudeSession.identity(kind: root.kind, name: name, pid: pid),
            pid: pid,
            kind: root.kind,
            name: name,
            workingDirectory: directory,
            startedAt: startedAt,
            childCount: children.count,
            activeSince: activeSince
        )
    }
}
