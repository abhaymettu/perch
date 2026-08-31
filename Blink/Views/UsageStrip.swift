import SwiftUI

struct UsageStrip: View {
    let block: UsageBlock

    var body: some View {
        HStack(spacing: 0) {
            cell(block.remainingLabel, caption: "left")
            Spacer()
            cell(money(block.costUSD), caption: "block")
            Spacer()
            cell(money(block.costPerHour), caption: "per hour")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private func cell(_ value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
            Text(caption)
                .font(.system(size: 9))
                .foregroundStyle(.secondary.opacity(0.7))
        }
    }

    private func money(_ amount: Double) -> String {
        String(format: "$%.0f", amount)
    }
}

// MARK: - Rows

struct LaunchAgentRowView: View {
    @Environment(AppState.self) private var appState
    let agent: LaunchAgent

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            ColorBar(color: agent.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(agent.label.replacingOccurrences(of: "com.abhay.", with: ""))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Text(agent.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(agent.hasFailed ? Color.alert : .secondary)
            }

            Spacer()

            // Read-only: reveal only. No start, no stop, no unload.
            if isHovered {
                RowAction(symbol: "folder", help: "Reveal plist") {
                    appState.reveal(path: agent.plistPath)
                }
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
            ColorBar(color: .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(job.command)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Text(job.schedule)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .hoverRow()
    }
}
