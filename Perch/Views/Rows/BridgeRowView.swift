import SwiftUI

/// Same anatomy as a daemon row — colour bar, name, one detail on the right —
/// because it is the same kind of fact. A second visual language for one line
/// is how a panel stops looking like one thing.
struct BridgeRowView: View {
    let status: BridgeStatus

    var body: some View {
        HStack(spacing: 0) {
            ColorBar(color: status.color)

            Text(status.headline)
                .font(.rowTitle)
                .foregroundStyle(status.isHealthy ? Color.ink : Color.alert)
                .lineLimit(1)

            Spacer(minLength: 8)

            // The detail slot carries the cause when there is one, the clock
            // when there is not — the same slot a daemon row spends on
            // "running" or on "exit 5".
            if let qualifier = status.qualifier {
                Text(qualifier)
                    .font(.rowMeta)
                    .foregroundStyle(Color.inkMuted)
                    .lineLimit(1)
            } else {
                if status.queueDepth > 0 {
                    Text("\(status.queueDepth) queued")
                        .font(.rowMeta)
                        .foregroundStyle(Color.inkMuted)
                        .monospacedDigit()
                        .padding(.trailing, 6)
                }

                if let age = status.age {
                    Text(Age.short(age))
                        .font(.rowNumber)
                        .foregroundStyle(Color.inkFaint)
                        .monospacedDigit()
                }
            }
        }
        .hoverRow()
        .help(status.help)
    }
}
