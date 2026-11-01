import SwiftUI

struct LaunchAgentRowView: View {
    @Environment(AppState.self) private var appState
    let agent: LaunchAgent

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                Text(agent.shortLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)

                Spacer(minLength: 2)

                // Use the scanner's verdict rather than treating every
                // non-failing launchd job as a running process.
                PerchStateLabel(
                    word: agent.hasFailed ? "failed" : agent.detail,
                    state: agent.hasFailed ? .warning : .healthy
                )
                .monospacedDigit()
                .contentTransition(.numericText())

                if isHovered {
                    RowAction(symbol: "folder", help: "Reveal plist") {
                        appState.reveal(path: agent.plistPath)
                    }
                    .transition(.opacity)
                }
            }
            .frame(minHeight: 17)

            if agent.hasFailed {
                Text(agent.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .hoverRow { isHovered = $0 }
        .help(agent.detail)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(agent.shortLabel)
        .accessibilityValue("\(agent.hasFailed ? "failed, " : "")\(agent.detail)")
        .accessibilityAction(named: Text("Reveal plist")) {
            appState.reveal(path: agent.plistPath)
        }
    }
}

struct CronJobRowView: View {
    let job: CronJob

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                Text(job.command)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)

                Spacer(minLength: 2)

                PerchStateLabel(word: "scheduled", state: .working)
            }
            .frame(minHeight: 17)

            Text(job.schedule)
                .font(.system(size: 11))
                .foregroundStyle(Color.inkMuted)
                .monospacedDigit()
                .lineLimit(1)
        }
        .hoverRow()
        .help("\(job.command) · \(job.schedule)")
        .accessibilityElement(children: .combine)
    }
}