import SwiftUI

struct SimulatorRowView: View {
    @Environment(AppState.self) private var appState
    let simulator: Simulator

    @State private var isHovered = false

    private var restartState: AppState.RestartState? {
        appState.simulatorRestartStates[simulator.id]
    }

    private var isRestarting: Bool { restartState == .restarting }

    private var failureMessage: String? {
        if case .failed(let message) = restartState { return message }
        return nil
    }

    private var stateWord: String {
        if isRestarting { return "relaunching…" }
        if failureMessage != nil { return "failed to relaunch" }
        return "running"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            header

            if let failureMessage {
                FailureBox(message: failureMessage)
                    .padding(.horizontal, HoverRowStyle.horizontalPadding)
                    .padding(.bottom, 6)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: failureMessage)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                Text(simulator.runningApp?.displayName ?? simulator.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)

                Spacer(minLength: 2)

                if failureMessage == nil {
                    PerchStateLabel(
                        word: stateWord,
                        state: isRestarting ? .working : .healthy
                    )
                }
            }
            .frame(minHeight: 17)

            if failureMessage != nil {
                PerchStateLabel(word: "failed to relaunch", state: .warning)
                    .padding(.top, 1)
            }

            HStack(spacing: 4) {
                Text(
                    simulator.runningApp == nil
                        ? simulator.runtime
                        : "\(simulator.name) · \(simulator.runtime)"
                )
                .font(.system(size: 11))
                .foregroundStyle(Color.inkMuted)
                .lineLimit(1)

                Spacer(minLength: 0)

                if isHovered && !isRestarting {
                    actions
                        .transition(.opacity)
                }
            }
            .frame(minHeight: 16)
        }
        .hoverRow { isHovered = $0 }
        .onTapGesture {
            guard !isRestarting else { return }
            appState.focusSimulator(simulator)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(simulator.runningApp?.displayName ?? simulator.name)
        .accessibilityValue("\(stateWord), \(simulator.name), \(simulator.runtime)")
        .accessibilityAction(named: Text("Focus simulator")) {
            guard !isRestarting else { return }
            appState.focusSimulator(simulator)
        }
        .accessibilityAction(named: Text("Relaunch app")) {
            guard !isRestarting, simulator.runningApp != nil else { return }
            appState.restartApp(in: simulator)
        }
        .accessibilityAction(named: Text(failureMessage == nil ? "Shutdown simulator" : "Dismiss")) {
            guard !isRestarting else { return }
            stopOrDismiss()
        }
        .help(failureMessage ?? "\(simulator.name) · \(simulator.runtime)")
    }

    private var actions: some View {
        HStack(spacing: RowAction.spacing) {
            if simulator.runningApp != nil {
                RowAction(symbol: "arrow.clockwise", help: "Relaunch app") {
                    appState.restartApp(in: simulator)
                }
            }

            RowAction(
                symbol: "xmark",
                help: failureMessage == nil ? "Shutdown simulator" : "Dismiss",
                tint: .alert
            ) {
                stopOrDismiss()
            }
        }
    }

    private func stopOrDismiss() {
        if failureMessage == nil {
            appState.stopSimulator(simulator)
        } else {
            appState.dismissSimulatorFailure(simulator)
        }
    }
}