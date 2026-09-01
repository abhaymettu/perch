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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            if let failureMessage {
                FailureBox(message: failureMessage)
                    .padding(.leading, HoverRowStyle.horizontalPadding + ColorBar.gutter)
                    .padding(.trailing, HoverRowStyle.horizontalPadding)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: failureMessage)
    }

    private var header: some View {
        HStack(spacing: 0) {
            ColorBar(color: barColor, isWorking: isRestarting)

            Text(simulator.runningApp?.displayName ?? simulator.name)
                .font(.rowTitle)
                .foregroundStyle(Color.ink)
                .lineLimit(1)

            Spacer(minLength: 8)

            if isHovered && !isRestarting {
                actions
                    .transition(.opacity)
            } else {
                subtitle
                    .transition(.opacity)
            }
        }
        .opacity(isRestarting ? 0.4 : 1)
        .allowsHitTesting(!isRestarting)
        .animation(.easeOut(duration: 0.2), value: isRestarting)
        .hoverRow { isHovered = $0 }
        .onTapGesture { appState.focusSimulator(simulator) }
    }
}

// MARK: - Pieces

private extension SimulatorRowView {
    var barColor: Color {
        failureMessage == nil ? .xcode : Color.alert
    }

    @ViewBuilder
    var subtitle: some View {
        if isRestarting {
            Text("relaunching…")
                .font(.rowMeta)
                .foregroundStyle(Color.inkFaint)
                .lineLimit(1)
        } else if failureMessage != nil {
            Text("failed to relaunch")
                .font(.rowMeta)
                .foregroundStyle(Color.alert)
                .lineLimit(1)
        } else {
            Text("\(simulator.name) · \(simulator.runtime)")
                .font(.rowMeta)
                .foregroundStyle(Color.inkFaint)
                .lineLimit(1)
        }
    }

    var actions: some View {
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
                if failureMessage == nil {
                    appState.stopSimulator(simulator)
                } else {
                    appState.dismissSimulatorFailure(simulator)
                }
            }
        }
    }
}
