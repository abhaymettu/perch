import Foundation
import SwiftUI

@Observable
final class AppState {
    var servers: [DevServer] = []
    var simulators: [Simulator] = []
    var sessions: [ClaudeSession] = []
    var agents: [LaunchAgent] = []
    var cronJobs: [CronJob] = []

    let usage: LimitsMonitor

    @ObservationIgnored
    @AppStorage("showDesktopHelpers") var showDesktopHelpers = false

    private var isScanning = false
    var isInitialLoad = true
    var lastEvent: PerchEvent = .idle

    var restartStates: [Int: RestartState] = [:]

    var simulatorRestartStates: [String: RestartState] = [:]

    private static let pollingInterval: TimeInterval = 3.0

    private var timer: Timer?
    private var killedPIDs: Set<Int> = []

    // Keyed by the killed PID, not the port: a port that never falls silent
    // would otherwise stay suppressed forever.
    private var killedPorts: [Int: Int] = [:]
    private var killedSimUDIDs: Set<String> = []
    private var killedSessionIDs: Set<String> = []

    private var relaunched: [Int: RelaunchedServer] = [:]

    private(set) var isActive: Bool = false
    var totalCount: Int { servers.count + simulators.count + sessions.count }

    /// Turns the menubar owl red: a session running well past its kind's
    /// threshold, or a daemon that exited nonzero.
    var hasProblem: Bool {
        sessions.contains(where: \.isStale) || agents.contains(where: \.hasFailed)
    }

    var hasAnything: Bool {
        !servers.isEmpty || !simulators.isEmpty || !sessions.isEmpty
            || !agents.isEmpty || !cronJobs.isEmpty
    }

    // MARK: - Perch Events

    enum PerchEvent: Equatable {
        case idle
        case active
        case scanning
        case newDetected
        case killed
        case restarting
        case failed
    }

    // MARK: - Restart State

    enum RestartState: Equatable {
        case restarting
        case failed(String)
    }

    // MARK: - Lifecycle

    init() {
        usage = LimitsMonitor()
        startPolling()
    }

    deinit {
        timer?.invalidate()
    }

    #if DEBUG
    /// Frozen state for the preview harness: no poll, no network, so a
    /// screenshot of round N is comparable to a screenshot of round N+1.
    init(frozen scenario: PreviewScenario) {
        usage = LimitsMonitor(frozen: scenario.limits)
        servers = scenario.servers
        simulators = scenario.simulators
        sessions = scenario.sessions
        agents = scenario.agents
        cronJobs = scenario.cronJobs
        restartStates = scenario.restartFailures.mapValues { .failed($0) }
        isInitialLoad = false
        isActive = totalCount > 0
        lastEvent = totalCount > 0 ? .active : .idle
    }
    #endif

    // MARK: - Polling

    func startPolling() {
        Task { await refresh() }

        timer = Timer.scheduledTimer(withTimeInterval: Self.pollingInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.refresh() }
        }
    }

    func refresh() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        let previousCount = totalCount

        async let scannedServers = scanServers()
        async let scannedSims = SimulatorMonitor.scan()
        async let scannedSessions = ClaudeScanner.scan(includeDesktop: showDesktopHelpers)
        async let scannedAgents = LaunchAgentScanner.scan()
        async let scannedCron = CronScanner.scan()

        let (newServers, newSims) = await (scannedServers, scannedSims)
        let (newSessions, newAgents, newCron) = await (scannedSessions, scannedAgents, scannedCron)

        let activePIDs = Set(newServers.map(\.pid))
        killedPIDs = killedPIDs.intersection(activePIDs)
        killedPorts = killedPorts.filter { activePIDs.contains($0.value) }
        let activeSimUDIDs = Set(newSims.map(\.id))
        killedSimUDIDs = killedSimUDIDs.intersection(activeSimUDIDs)
        killedSessionIDs = killedSessionIDs.intersection(Set(newSessions.map(\.id)))

        let filteredServers = newServers.filter {
            !killedPIDs.contains($0.pid) && killedPorts[$0.port] == nil
        }
        let filteredSims = newSims.filter { !killedSimUDIDs.contains($0.id) }
        let filteredSessions = newSessions.filter { !killedSessionIDs.contains($0.id) }

        if sessions != filteredSessions { sessions = filteredSessions }
        if agents != newAgents { agents = newAgents }
        if cronJobs != newCron { cronJobs = newCron }

        clearStaleFailures(among: filteredServers)
        let mergedServers = preservingRestartingRows(filteredServers)

        if servers != mergedServers {
            servers = mergedServers
        }
        if simulators != filteredSims {
            simulators = filteredSims
        }
        if isInitialLoad {
            isInitialLoad = false
        }

        let nowActive = totalCount > 0
        if isActive != nowActive {
            isActive = nowActive
        }

        if totalCount > previousCount {
            lastEvent = .newDetected
            try? await Task.sleep(for: .seconds(0.6))
        }

        guard !hasRestartInFlight else { return }

        let newEvent: PerchEvent = totalCount > 0 ? .active : .idle
        if lastEvent != newEvent {
            lastEvent = newEvent
        }
    }

    private var hasRestartInFlight: Bool {
        restartStates.values.contains(.restarting)
            || simulatorRestartStates.values.contains(.restarting)
    }

    private func clearStaleFailures(among scanned: [DevServer]) {
        for server in scanned {
            if case .failed = restartStates[server.port] {
                restartStates[server.port] = nil
            }
        }
    }

    private func preservingRestartingRows(_ scanned: [DevServer]) -> [DevServer] {
        guard !restartStates.isEmpty else { return scanned }

        var merged = scanned
        for (port, _) in restartStates where !merged.contains(where: { $0.port == port }) {
            if let previous = servers.first(where: { $0.port == port }) {
                merged.append(previous)
            }
        }
        return merged.sorted { $0.port < $1.port }
    }

    // MARK: - Actions

    func killServer(_ server: DevServer) {
        lastEvent = .killed
        restartStates[server.port] = nil
        killedPIDs.insert(server.pid)
        killedPorts[server.port] = server.pid
        withAnimation(.easeOut(duration: 0.3)) {
            servers.removeAll { $0.port == server.port }
        }
        killProcessTree(pid: server.pid)
    }

    func killSession(_ session: ClaudeSession) {
        lastEvent = .killed
        killedSessionIDs.insert(session.id)
        withAnimation(.easeOut(duration: 0.3)) {
            sessions.removeAll { $0.id == session.id }
        }
        killProcessTree(pid: session.pid)
    }

    func revealSession(_ session: ClaudeSession) {
        guard !session.workingDirectory.isEmpty else { return }
        reveal(path: session.workingDirectory)
    }

    func reveal(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func dismissFailed(_ server: DevServer) {
        restartStates[server.port] = nil
        withAnimation(.easeOut(duration: 0.3)) {
            servers.removeAll { $0.port == server.port }
        }
    }

    func restartApp(in simulator: Simulator) {
        guard let app = simulator.runningApp,
              simulatorRestartStates[simulator.id] != .restarting else { return }

        lastEvent = .restarting
        withAnimation(.easeOut(duration: 0.2)) {
            simulatorRestartStates[simulator.id] = .restarting
        }

        Task {
            let failure = await SimulatorMonitor.relaunchApp(
                udid: simulator.id,
                bundleID: app.bundleID
            )
            finishSimulatorRestart(udid: simulator.id, failure: failure)
        }
    }

    private func finishSimulatorRestart(udid: String, failure: String?) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.25)) {
                self.simulatorRestartStates[udid] = failure.map { .failed($0) }
                if failure != nil { self.lastEvent = .failed }
            }
        }
    }

    func dismissSimulatorFailure(_ simulator: Simulator) {
        withAnimation(.easeOut(duration: 0.25)) {
            simulatorRestartStates[simulator.id] = nil
        }
    }

    func stopSimulator(_ simulator: Simulator) {
        lastEvent = .killed
        simulatorRestartStates[simulator.id] = nil
        killedSimUDIDs.insert(simulator.id)
        withAnimation(.easeOut(duration: 0.3)) {
            simulators.removeAll { $0.id == simulator.id }
        }
        Task {
            await SimulatorMonitor.shutdown(udid: simulator.id)
        }
    }

    func stopAllServers() {
        lastEvent = .killed

        for server in servers {
            restartStates[server.port] = nil
            killedPIDs.insert(server.pid)
            killedPorts[server.port] = server.pid
            killProcessTree(pid: server.pid)
        }

        cascadeRemoval(count: servers.count) { self.servers.removeFirst() }
    }

    func shutDownAllSimulators() {
        lastEvent = .killed

        for simulator in simulators {
            simulatorRestartStates[simulator.id] = nil
            killedSimUDIDs.insert(simulator.id)
        }

        Task { await SimulatorMonitor.shutdownAll() }
        cascadeRemoval(count: simulators.count) { self.simulators.removeFirst() }
    }

    private func cascadeRemoval(count: Int, removeFirst: @escaping () -> Void) {
        let stagger = 0.1

        for index in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * stagger) {
                withAnimation(.easeOut(duration: 0.25)) { removeFirst() }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Double(count) * stagger + 0.3) {
            self.lastEvent = self.totalCount > 0 ? .active : .idle
        }
    }

    private func killProcessTree(pid: Int) {
        let p = pid_t(pid)
        kill(p, SIGTERM)
        Task {
            _ = await Shell.run("/usr/bin/pkill", arguments: ["-TERM", "-P", "\(pid)"])

            try? await Task.sleep(for: .seconds(1))
            kill(p, SIGKILL)
            _ = await Shell.run("/usr/bin/pkill", arguments: ["-KILL", "-P", "\(pid)"])
        }
    }

    func openInBrowser(_ server: DevServer) {
        guard let url = server.localhostURL else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Restart

    private static let portFreeTimeout: TimeInterval = 6
    private static let portReturnTimeout: TimeInterval = 30
    private static let exitGracePeriod: TimeInterval = 1

    private enum RelaunchOutcome {
        case listening
        case exited
        case timedOut
    }

    func restartServer(_ server: DevServer) {
        guard restartStates[server.port] != .restarting else { return }

        lastEvent = .restarting
        withAnimation(.easeOut(duration: 0.2)) {
            restartStates[server.port] = .restarting
        }

        Task { await performRestart(server) }
    }

    private func performRestart(_ server: DevServer) async {
        guard !server.projectPath.isEmpty,
              let target = await ProcessResolver.relaunchTarget(
                  pid: server.pid,
                  projectPath: server.projectPath
              ) else {
            finishRestart(port: server.port, failure: "Couldn't read the original command.")
            return
        }

        killProcessTree(pid: target.pid)
        killedPIDs.insert(server.pid)
        killedPIDs.insert(target.pid)

        guard await waitForPort(server.port, listening: false, timeout: Self.portFreeTimeout) else {
            finishRestart(port: server.port, failure: "Port \(server.port) never freed up.")
            return
        }

        killedPIDs.remove(server.pid)
        killedPIDs.remove(target.pid)
        killedPorts[server.port] = nil

        let relaunchedServer: RelaunchedServer
        do {
            relaunchedServer = try RelaunchedServer(
                executable: target.executablePath,
                arguments: target.arguments,
                directory: server.projectPath
            )
        } catch {
            finishRestart(port: server.port, failure: "Couldn't relaunch: \(error.localizedDescription)")
            return
        }

        relaunched[server.port] = relaunchedServer

        let outcome = await waitForServer(relaunchedServer, port: server.port)
        let tail = relaunchedServer.outputTail()

        switch outcome {
        case .listening:
            finishRestart(port: server.port, failure: nil)

        case .exited:
            finishRestart(
                port: server.port,
                failure: tail.isEmpty ? relaunchedServer.exitDescription : tail
            )

        case .timedOut:
            finishRestart(
                port: server.port,
                failure: tail.isEmpty
                    ? "Running, but nothing is listening on \(server.port) yet."
                    : tail
            )
        }
    }

    private func finishRestart(port: Int, failure: String?) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.25)) {
                if let failure {
                    self.restartStates[port] = .failed(failure)
                    self.lastEvent = .failed
                } else {
                    self.restartStates[port] = nil
                }
            }
        }
    }

    private func waitForServer(_ relaunched: RelaunchedServer, port: Int) async -> RelaunchOutcome {
        let deadline = Date().addingTimeInterval(Self.portReturnTimeout)

        while Date() < deadline {
            if await isPortListening(port) { return .listening }

            if !relaunched.isRunning {
                try? await Task.sleep(for: .seconds(Self.exitGracePeriod))
                return await isPortListening(port) ? .listening : .exited
            }

            try? await Task.sleep(for: .seconds(0.4))
        }

        return await isPortListening(port) ? .listening : .timedOut
    }

    private func waitForPort(_ port: Int, listening: Bool, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let interval: TimeInterval = 0.4

        while Date() < deadline {
            if await isPortListening(port) == listening { return true }
            try? await Task.sleep(for: .seconds(interval))
        }
        return await isPortListening(port) == listening
    }

    private func isPortListening(_ port: Int) async -> Bool {
        let output = await Shell.run(
            "/usr/sbin/lsof",
            arguments: ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-t"]
        )
        return !(output?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}
