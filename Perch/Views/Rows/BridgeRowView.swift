import SwiftUI

struct BridgeRowView: View {
    let status: BridgeStatus

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded: Bool

    init(status: BridgeStatus) {
        self.status = status
        _expanded = State(initialValue: !status.isHealthy)
    }

    private enum StageState {
        case ok, failed, unchecked
    }

    private let names = ["Poller", "GitHub", "Queue", "Vault"]

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
        case .unchecked: return "unchecked"
        case .failed: return ["down", "failing", "stuck", "broken"][index]
        case .ok: return "ok"
        }
    }

    private func mark(at index: Int) -> PerchMark {
        switch state(at: index) {
        case .ok: return .healthy
        case .failed: return .warning
        case .unchecked: return .unchecked
        }
    }

    private var cycle: String {
        status.age.map { "Last cycle \(Age.short($0)) ago" } ?? "No cycle recorded"
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
        VStack(spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                    expanded.toggle()
                }
                requestLayout()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "link")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.inkMuted)
                        .frame(width: 18, height: 18)
                        .accessibilityHidden(true)

                    Text("Bridge")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.ink)

                    Spacer(minLength: 2)

                    PerchStateLabel(
                        word: status.isHealthy ? "Up to date" : "Degraded",
                        state: status.isHealthy ? .healthy : .warning
                    )

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.inkFaint)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(PerchPlainButtonStyle())
            .accessibilityLabel("Bridge, \(status.isHealthy ? "Up to date" : "Degraded")")
            .accessibilityValue("\(expanded ? "expanded" : "collapsed"), \(accessibilitySummary)")
            .accessibilityHint(expanded ? "Collapse bridge details" : "Expand bridge details")

            if expanded {
                detail
                    .transition(.opacity)
            }
        }
        .background(expanded ? Color.black.opacity(0.10) : Color.clear)
        .perchGlassCard()
        .help([Optional(status.help), checkHint].compactMap { $0 }.joined(separator: " · "))
        .onChange(of: failureIndex) { _, newValue in
            if newValue != nil { expanded = true }
            requestLayout()
        }
        .onReceive(NotificationCenter.default.publisher(for: .perchPanelWillOpen)) { _ in
            expanded = !status.isHealthy
            requestLayout()
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            PerchHairline()

            VStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { index in
                    HStack(spacing: 7) {
                        PerchStatusMark(state: mark(at: index))
                            .foregroundStyle(
                                state(at: index) == .failed ? Color.alert : Color.inkMuted
                            )

                        Text(names[index])
                            .font(.system(size: 12))
                            .foregroundStyle(Color.ink)

                        Spacer(minLength: 4)

                        Text(word(at: index))
                            .font(.system(size: 11))
                            .foregroundStyle(
                                state(at: index) == .failed ? Color.alert : Color.inkMuted
                            )
                    }
                    .frame(minHeight: 25)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.vertical, 5)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Bridge pipeline in order")

            PerchHairline()

            HStack(spacing: 4) {
                Text("\(status.queueDepth) queued")
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
                Text(cycle)
                    .contentTransition(.numericText())
            }
            .font(.system(size: 11))
            .foregroundStyle(Color.inkMuted)
            .monospacedDigit()
            .padding(.top, 8)

            if let checkHint {
                Text(checkHint)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 7)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 11)
    }

    private var accessibilitySummary: String {
        let stages = (0..<4).map { "\(names[$0]) \(word(at: $0))" }
        return (
            stages + ["\(status.queueDepth) queued", cycle] +
            [checkHint].compactMap { $0 }
        ).joined(separator: ", ")
    }

    private func requestLayout() {
        NotificationCenter.default.post(name: .perchPanelLayoutChanged, object: nil)
    }
}