import SwiftUI

struct ClaudeSessionRowView: View {
    @Environment(AppState.self) private var appState
    let session: ClaudeSession

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            ColorBar(color: session.isStale ? .alert : session.kind.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(Age.short(session.displayAge))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(session.isStale ? Color.alert : .secondary)

                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isHovered {
                // No restart: relaunching a session means restoring terminal
                // and tmux context we cannot reconstruct.
                RowAction(symbol: "xmark", help: "Kill session", tint: .alert) {
                    appState.killSession(session)
                }
                .transition(.opacity)
            }
        }
        .hoverRow { isHovered = $0 }
        .onTapGesture { appState.revealSession(session) }
    }

    private var subtitle: String {
        var parts = [session.kind.label]
        if session.childCount > 0 {
            parts.append("\(session.childCount) child\(session.childCount == 1 ? "" : "ren")")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Age formatting

enum Age {
    /// "17h", "42m", "3d" — the panel is 320pt wide, so a duration gets one unit.
    static func short(_ interval: TimeInterval) -> String {
        let seconds = Int(max(interval, 0))
        switch seconds {
        case ..<60:     return "\(seconds)s"
        case ..<3600:   return "\(seconds / 60)m"
        case ..<86_400: return "\(seconds / 3600)h"
        default:        return "\(seconds / 86_400)d"
        }
    }
}
