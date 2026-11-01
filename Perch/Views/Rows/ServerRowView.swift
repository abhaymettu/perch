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

    private var frameworkLabel: String {
        server.framework == .unknown ? server.command : server.framework.rawValue
    }

    private var stateWord: String {
        if isRestarting { return "restarting…" }
        if failureMessage != nil { return "failed to restart" }
        return "live"
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
            HStack(spacing: 4) {
                Text(server.projectName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)

                Text("· :\(server.port)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.inkMuted)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .fixedSize()

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
                PerchStateLabel(word: "failed to restart", state: .warning)
                    .padding(.top, 1)
            }

            HStack(spacing: 4) {
                Text(frameworkLabel)
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
            guard !isRestarting, failureMessage == nil else { return }
            appState.openInBrowser(server)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(server.projectName), port \(server.port)")
        .accessibilityValue("\(stateWord), \(frameworkLabel)")
        .accessibilityAction(named: Text("Open in browser")) {
            guard !isRestarting, failureMessage == nil else { return }
            appState.openInBrowser(server)
        }
        .accessibilityAction(named: Text("Restart server")) {
            guard !isRestarting else { return }
            appState.restartServer(server)
        }
        .accessibilityAction(named: Text(failureMessage == nil ? "Stop server" : "Dismiss")) {
            guard !isRestarting else { return }
            stopOrDismiss()
        }
        .help(failureMessage ?? "\(frameworkLabel) · Open in browser")
    }

    private var actions: some View {
        HStack(spacing: RowAction.spacing) {
            RowAction(symbol: "arrow.clockwise", help: "Restart server") {
                appState.restartServer(server)
            }

            RowAction(
                symbol: "xmark",
                help: failureMessage == nil ? "Stop server" : "Dismiss",
                tint: .alert
            ) {
                stopOrDismiss()
            }
        }
    }

    private func stopOrDismiss() {
        if failureMessage == nil {
            appState.killServer(server)
        } else {
            appState.dismissFailed(server)
        }
    }
}