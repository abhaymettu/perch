import SwiftUI

struct LaunchAgentRowView: View {
    @Environment(AppState.self) private var appState
    let agent: LaunchAgent

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            ColorBar(color: agent.color)

            Text(agent.label.replacingOccurrences(of: "com.abhay.", with: ""))
                .font(.rowTitle)
                .foregroundStyle(Color.ink)
                .lineLimit(1)

            Spacer(minLength: 8)

            // Read-only: reveal only. No start, no stop, no unload.
            if isHovered {
                RowAction(symbol: "folder", help: "Reveal plist") {
                    appState.reveal(path: agent.plistPath)
                }
                .transition(.opacity)
            } else {
                Text(agent.detail)
                    .font(.rowMeta)
                    .foregroundStyle(agent.hasFailed ? Color.alert : Color.inkFaint)
                    .lineLimit(1)
                    .transition(.opacity)
            }
        }
        .hoverRow { isHovered = $0 }
    }
}

struct CronJobRowView: View {
    let job: CronJob

    var body: some View {
        HStack(spacing: 0) {
            ColorBar(color: .inkFaint)

            Text(job.command)
                .font(.rowTitle)
                .foregroundStyle(Color.ink)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(job.schedule)
                .font(.rowNumber)
                .foregroundStyle(Color.inkFaint)
                .lineLimit(1)
        }
        .hoverRow()
    }
}
