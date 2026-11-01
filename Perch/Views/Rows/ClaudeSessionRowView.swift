import SwiftUI

struct ClaudeSessionRowView: View {
    @Environment(AppState.self) private var appState
    let session: ClaudeSession

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                Text(session.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)

                Spacer(minLength: 2)

                PerchStateLabel(
                    word: session.isStale ? "stale" : "active",
                    state: session.isStale ? .warning : .healthy
                )

                if isHovered {
                    RowAction(symbol: "xmark", help: "Kill session", tint: .alert) {
                        appState.killSession(session)
                    }
                    .transition(.opacity)
                }
            }
            .frame(minHeight: 17)

            HStack(spacing: 4) {
                Text(
                    session.isStale
                        ? "no heartbeat for \(Age.short(session.displayAge))"
                        : subtitle
                )
                .lineLimit(1)

                if !session.isStale {
                    Spacer(minLength: 0)
                    Text(Age.short(session.displayAge))
                        .contentTransition(.numericText())
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(Color.inkMuted)
            .monospacedDigit()
        }
        .hoverRow { isHovered = $0 }
        .onTapGesture { appState.revealSession(session) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(session.name)
        .accessibilityValue(
            "\(session.isStale ? "stale, no heartbeat for" : "active, age") \(Age.short(session.displayAge)), \(subtitle)"
        )
        .accessibilityAction(named: Text("Reveal session")) {
            appState.revealSession(session)
        }
        .accessibilityAction(named: Text("Kill session")) {
            appState.killSession(session)
        }
        .help("\(subtitle) · Click to reveal session")
    }

    private var subtitle: String {
        var parts = [session.kind.label]
        if session.childCount > 0 {
            parts.append("\(session.childCount)×")
        }
        return parts.joined(separator: " · ")
    }
}

enum Age {
    static func short(_ interval: TimeInterval) -> String {
        let seconds = Int(max(interval, 0))
        switch seconds {
        case ..<60: return "\(seconds)s"
        case ..<3600: return "\(seconds / 60)m"
        case ..<86_400: return "\(seconds / 3600)h"
        default: return "\(seconds / 86_400)d"
        }
    }
}