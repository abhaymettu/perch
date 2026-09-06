import Foundation

/// One live tmux/herdr task: a workspace+tab pair and the status text Claude
/// Code left in its terminal title. Sourced from `~/.perch-bridge/status.json`,
/// written by `Scripts/bridge-writer.py` polling `herdr pane/workspace list`
/// from a dedicated tmux window. Replaces the exec-poller-era `BridgeStatus`
/// now that the poller it read no longer exists — see vault
/// 05-Bridge/lane-cutover-2026-09-06.md.
struct BridgeTask: Identifiable, Equatable, Decodable {
    let id: String
    let workspaceId: String
    let workspaceLabel: String
    let tabLabel: String
    let statusText: String?
    let updatedAt: Double

    enum CodingKeys: String, CodingKey {
        case id = "tab_id"
        case workspaceId = "workspace_id"
        case workspaceLabel = "workspace_label"
        case tabLabel = "tab_label"
        case statusText = "status_text"
        case updatedAt = "updated_at"
    }
}

enum BridgeTasks {
    private static let file = URL(
        fileURLWithPath: ("~/.perch-bridge/status.json" as NSString).expandingTildeInPath
    )
    private static let herdrPath = "/opt/homebrew/bin/herdr"

    /// A writer that stalls (window killed, tmux server dead) leaves the file
    /// in place, so age on the whole snapshot — not just its mtime — is what
    /// tells a frozen bridge from a live one.
    private static let staleAfter: TimeInterval = 30

    private struct Snapshot: Decodable {
        let generatedAt: Double
        let tasks: [BridgeTask]

        enum CodingKeys: String, CodingKey {
            case generatedAt = "generated_at"
            case tasks
        }
    }

    /// nil when the writer has never run or has gone stale — this Mac's
    /// bridge is not to be trusted, not merely empty.
    static func read() -> [BridgeTask]? {
        guard let data = try? Data(contentsOf: file),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              Date().timeIntervalSince1970 - snapshot.generatedAt < staleAfter
        else { return nil }
        return snapshot.tasks
    }

    /// `herdr workspace/tab focus` switch the content of an already-open,
    /// already-attached herdr client window but do not raise it over other
    /// apps — verified empirically, not assumed. Activating Ghostty first is
    /// what actually brings the window forward.
    static func focus(workspaceId: String, tabId: String) {
        Task {
            _ = await Shell.run("/usr/bin/open", arguments: ["-a", "Ghostty"])
            _ = await Shell.run(herdrPath, arguments: ["workspace", "focus", workspaceId])
            _ = await Shell.run(herdrPath, arguments: ["tab", "focus", tabId])
        }
    }
}
