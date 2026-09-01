import Foundation
import SwiftUI

struct ClaudeSession: Identifiable, Hashable {
    /// A lane is identified by its name so the row survives a lane restart.
    /// Everything else is identified by PID — a terminal session has no stable name.
    static func identity(kind: SessionKind, name: String, pid: Int) -> String {
        kind == .remoteControl ? "lane:\(name)" : "\(kind.rawValue):\(pid)"
    }

    let id: String
    let pid: Int
    let kind: SessionKind
    let name: String
    let workingDirectory: String
    let startedAt: Date

    /// Claude processes descending from this one — a lane's live session, an
    /// interactive session's tool calls.
    let childCount: Int

    /// Set when a lane is driving a live session, from that child's start time.
    let activeSince: Date?

    /// A lane is judged by how long its session has been open, not by the
    /// lane's own uptime — an idle lane running for a week is fine.
    var displayAge: TimeInterval { Date().timeIntervalSince(activeSince ?? startedAt) }

    /// A lane with no live session is idle, not stale — `displayAge` falls back
    /// to the lane's own uptime, and lanes are up for days on purpose. Without
    /// this the panel cries wolf every morning.
    var isStale: Bool {
        if kind == .remoteControl && activeSince == nil { return false }
        return displayAge > kind.staleAfter
    }
}

// MARK: - Kind

enum SessionKind: String, CaseIterable {
    case remoteControl
    case interactive
    case headless
    case desktop

    var label: String {
        switch self {
        case .remoteControl: "lane"
        case .interactive:   "terminal"
        case .headless:      "headless"
        case .desktop:       "desktop app"
        }
    }

    var color: Color {
        switch self {
        case .remoteControl: Color(hex: 0xD97757)
        case .interactive:   Color(hex: 0x61C7B0)
        case .headless:      Color(hex: 0xB48EAD)
        case .desktop:       .secondary
        }
    }

    /// A headless session nobody is watching is the thing worth flagging;
    /// a terminal you are sitting in front of is not.
    var staleAfter: TimeInterval {
        switch self {
        case .headless:      4 * 3600
        case .remoteControl: 12 * 3600
        case .interactive:   24 * 3600
        case .desktop:       .infinity
        }
    }

    /// Declaration order is the panel order: lanes, then terminals, then
    /// headless workers, then the desktop app.
    var sortOrder: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}
