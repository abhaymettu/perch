import SwiftUI

struct ClaudeSessionRowView: View {
    @Environment(AppState.self) private var appState
    let session: ClaudeSession

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            ColorBar(color: session.isStale ? .alert : session.kind.color)

            Text(session.name)
                .font(.rowTitle)
                .foregroundStyle(Color.ink)
                .lineLimit(1)

            Spacer(minLength: 8)

            // The kind is context, not news: it steps aside for the action the
            // moment the row is the one you are pointing at.
            if isHovered {
                // No restart: relaunching a session means restoring terminal
                // and tmux context we cannot reconstruct.
                RowAction(symbol: "xmark", help: "Kill session", tint: .alert) {
                    appState.killSession(session)
                }
                .transition(.opacity)
            } else {
                Text(subtitle)
                    .font(.rowMeta)
                    .foregroundStyle(Color.inkFaint)
                    .lineLimit(1)
                    .transition(.opacity)
            }

            Text(Age.short(session.displayAge))
                .font(.rowNumber)
                .foregroundStyle(session.isStale ? Color.alert : Color.inkMuted)
                .monospacedDigit()
                .frame(width: 30, alignment: .trailing)
                .padding(.leading, 8)
        }
        .hoverRow { isHovered = $0 }
        .onTapGesture { appState.revealSession(session) }
    }

    private var subtitle: String {
        var parts = [session.kind.label]
        if session.childCount > 0 {
            parts.append("\(session.childCount)×")
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
