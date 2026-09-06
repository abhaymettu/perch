import SwiftUI

/// One tmux/herdr task. Tapping it focuses the workspace and tab, then
/// activates Ghostty so the window actually comes forward — `herdr focus`
/// alone only updates its internal state.
struct BridgeTaskRowView: View {
    let task: BridgeTask

    @State private var isHovered = false

    private var subtitle: String {
        task.statusText ?? "No status yet"
    }

    // A real Button, not `.onTapGesture` + `.accessibilityAddTraits(.isButton)`:
    // in this nonactivating NSPanel, neither a real click nor a synthetic
    // AXPress ever reached a tap gesture here (verified — both hit-tested to
    // the right AXButton, neither fired). Button's own hit-testing isn't
    // routed through the same path and does fire reliably.
    var body: some View {
        Button(action: focus) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(task.workspaceLabel) · \(task.tabLabel)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.inkMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.inkFaint)
                    .opacity(isHovered ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverRow { isHovered = $0 }
        .accessibilityLabel("\(task.workspaceLabel), \(task.tabLabel)")
        .accessibilityValue(subtitle)
        .accessibilityHint("Focus this task's window")
        .help("\(subtitle) · Click to focus")
    }

    private func focus() {
        NotificationCenter.default.post(name: .perchPanelShouldClose, object: nil)
        BridgeTasks.focus(workspaceId: task.workspaceId, tabId: task.id)
    }
}
