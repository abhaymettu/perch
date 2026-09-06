import SwiftUI

struct BridgeRowView: View {
    let status: BridgeStatus

    private enum StageState {
        case ok, failed, unchecked
    }

    private let names = ["POLLER", "GITHUB", "QUEUE", "VAULT"]

    // A downstream result is not evidence of health when an earlier stage
    // failed. Unchecked keeps that uncertainty visible instead of guessing.
    private var failureIndex: Int? {
        switch status.state {
        case .alive: nil
        case .pollerDown: 0
        case .pollFailing: 1
        case .queueStuck: 2
        case .vaultBroken: 3
        }
    }

    private func state(at index: Int) -> StageState {
        guard let failureIndex else { return .ok }
        if index < failureIndex { return .ok }
        return index == failureIndex ? .failed : .unchecked
    }

    private func word(at index: Int) -> String {
        switch state(at: index) {
        case .unchecked:
            return "unchecked"
        case .failed:
            return ["down", "failing", "stuck", "broken"][index]
        case .ok:
            switch index {
            case 0: return "alive"
            case 2: return "\(status.queueDepth) queued"
            default: return "ok"
            }
        }
    }

    private func tint(at index: Int) -> Color {
        switch state(at: index) {
        case .ok: .ok
        case .failed: .alert
        case .unchecked: .inkFaint
        }
    }

    private var headline: String {
        let prefix = "Bridge: "
        return status.headline.hasPrefix(prefix)
            ? String(status.headline.dropFirst(prefix.count))
            : status.headline
    }

    private var cycle: String {
        status.age.map { "last cycle \(Age.short($0)) ago" } ?? "no cycle recorded"
    }

    private var checkHint: String? {
        guard !status.isHealthy else { return nil }

        if let qualifier = status.qualifier {
            let subject = qualifier.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
            return "Check \(subject)"
        }

        switch status.state {
        case .pollerDown: return "Check launchd"
        case .vaultBroken: return "Check vault repo"
        default: return "Check bridge"
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                Text("Bridge")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.ink)

                Spacer(minLength: 4)

                Text(headline)
                    .font(.system(size: 10, weight: status.isHealthy ? .regular : .semibold))
                    .foregroundStyle(status.isHealthy ? Color.inkMuted : Color.alert)
                    .lineLimit(1)
            }
            .frame(height: 14)

            chain
                .frame(height: 30)

            HStack(spacing: 4) {
                Text(cycle)
                    .foregroundStyle(Color.inkMuted)
                    .layoutPriority(1)

                Spacer(minLength: 0)

                if let checkHint {
                    Text(checkHint)
                        .foregroundStyle(Color.ink)
                }
            }
            .font(.system(size: 8.5))
            .monospacedDigit()
            .lineLimit(1)
            .frame(height: 10)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .background(Color.panelSurface, in: RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color.panelRule, lineWidth: 1)
        }
        .help([status.help, checkHint].compactMap { $0 }.joined(separator: " · "))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.headline)
        .accessibilityValue(accessibilitySummary)
    }

    private var chain: some View {
        VStack(spacing: 1) {
            HStack(spacing: 0) {
                ForEach(0..<4) { index in
                    node(at: index)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 8)
            .background {
                GeometryReader { proxy in
                    Path { path in
                        let step = proxy.size.width / 4
                        for index in 0..<3 {
                            let start = step * (CGFloat(index) + 0.5) + 6
                            let end = step * (CGFloat(index) + 1.5) - 6
                            let middle = (start + end) / 2
                            path.move(to: CGPoint(x: start, y: 4))
                            path.addLine(to: CGPoint(x: end, y: 4))
                            path.move(to: CGPoint(x: middle - 2, y: 2))
                            path.addLine(to: CGPoint(x: middle, y: 4))
                            path.addLine(to: CGPoint(x: middle - 2, y: 6))
                        }
                    }
                    .stroke(Color.panelRule, lineWidth: 1)
                }
            }

            HStack(spacing: 0) {
                ForEach(0..<4) { index in
                    Text(names[index])
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(Color.inkMuted)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 10)

            HStack(spacing: 0) {
                ForEach(0..<4) { index in
                    Text(word(at: index))
                        .font(.system(size: 9, weight: state(at: index) == .failed ? .bold : .regular))
                        .foregroundStyle(state(at: index) == .failed ? Color.alert : Color.ink)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 10)
        }
    }

    private func node(at index: Int) -> some View {
        ZStack {
            switch state(at: index) {
            case .ok:
                Circle()
                    .strokeBorder(tint(at: index), lineWidth: 2)
            case .failed:
                Circle()
                    .fill(tint(at: index))

                // A cut-out exclamation remains distinct from both ring styles
                // when the card is viewed without colour.
                Path { path in
                    path.move(to: CGPoint(x: 4, y: 2))
                    path.addLine(to: CGPoint(x: 4, y: 4))
                    path.move(to: CGPoint(x: 4, y: 5.5))
                    path.addLine(to: CGPoint(x: 4, y: 6))
                }
                .stroke(Color.panelSurface, style: StrokeStyle(lineWidth: 1, lineCap: .round))
            case .unchecked:
                Circle()
                    .strokeBorder(tint(at: index), lineWidth: 0.5)
            }
        }
        .frame(width: 8, height: 8)
    }

    private var accessibilitySummary: String {
        let stages = (0..<4).map { "\(names[$0].capitalized) \(word(at: $0))" }
        return (stages + [cycle] + [checkHint].compactMap { $0 }).joined(separator: ", ")
    }
}
