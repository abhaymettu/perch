import SwiftUI

struct ServerRowView: View {
    @Environment(AppState.self) private var appState
    let server: DevServer

    @State private var isHovered = false

    private var restartState: AppState.RestartState? {
        appState.restartStates[server.port]
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

            Text(server.projectName)
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

            Text(verbatim: ":\(server.port)")
                .font(.rowNumber)
                .foregroundStyle(Color.inkMuted)
                .monospacedDigit()
                .frame(width: 38, alignment: .trailing)
                .padding(.leading, 8)
        }
        .opacity(isRestarting ? 0.4 : 1)
        .allowsHitTesting(!isRestarting)
        .animation(.easeOut(duration: 0.2), value: isRestarting)
        .hoverRow { isHovered = $0 }
        .onTapGesture {
            guard failureMessage == nil else { return }
            appState.openInBrowser(server)
        }
    }
}

// MARK: - Pieces

private extension ServerRowView {
    var barColor: Color {
        failureMessage == nil ? server.framework.color : Color.alert
    }

    @ViewBuilder
    var subtitle: some View {
        if isRestarting {
            Text("restarting…")
                .font(.rowMeta)
                .foregroundStyle(Color.inkFaint)
        } else if failureMessage != nil {
            Text("failed to restart")
                .font(.rowMeta)
                .foregroundStyle(Color.alert)
        } else {
            Text(server.framework == .unknown ? server.command : server.framework.rawValue)
                .font(.rowMeta)
                .foregroundStyle(Color.inkFaint)
                .lineLimit(1)
        }
    }

    var actions: some View {
        HStack(spacing: RowAction.spacing) {
            RowAction(symbol: "arrow.clockwise", help: "Restart server") {
                appState.restartServer(server)
            }

            RowAction(
                symbol: "xmark",
                help: failureMessage == nil ? "Stop server" : "Dismiss",
                tint: .alert
            ) {
                if failureMessage == nil {
                    appState.killServer(server)
                } else {
                    appState.dismissFailed(server)
                }
            }
        }
    }
}
