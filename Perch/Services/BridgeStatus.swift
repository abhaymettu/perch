import Foundation
import SwiftUI

/// The exec bridge in one line. launchd says whether the poller process is
/// alive; it cannot say whether the poller is reaching GitHub, draining its
/// queue, or writing the vault. The poller leaves that half in a small JSON
/// file each cycle, and this folds the two halves back into one verdict that
/// names which one died. Spec: vault 05-Bridge/perch-bridge-status.md.
struct BridgeStatus: Equatable {
    static let label = "com.abhay.exec-poller"
    static let file = URL(
        fileURLWithPath: ("~/.executor/bridge-status.json" as NSString).expandingTildeInPath
    )

    /// A queue nobody has drained in ten minutes is stuck, not busy.
    private static let queueStuckAfter: TimeInterval = 600

    /// Checked in this order, so the line names the deepest broken thing: a
    /// dead poller explains a stale file, and saying both would be two rows he
    /// has to combine himself.
    enum State {
        case alive, pollerDown, pollFailing, queueStuck, vaultBroken
    }

    let state: State
    /// Since the last cycle the poller wrote. nil when it has never written one.
    let age: TimeInterval?
    let queueDepth: Int

    var isHealthy: Bool { state == .alive }

    /// The name half of the line. The row splits it the way every other row in
    /// the panel splits one — title left, its qualifier in the detail slot —
    /// so "Bridge: poll failing (network/github/token)" still reads across in
    /// full without setting a 42-character string at title size.
    var headline: String {
        switch state {
        case .alive:       "Bridge: alive"
        case .pollerDown:  "Bridge: poller down"
        case .pollFailing: "Bridge: poll failing"
        case .queueStuck:  "Bridge: queue stuck"
        case .vaultBroken: "Bridge: vault write broken"
        }
    }

    /// Where to go looking, for the two failures that have more than one cause.
    var qualifier: String? {
        switch state {
        case .pollFailing: "(network/github/token)"
        case .queueStuck:  "(execd/allowlist)"
        default:           nil
        }
    }

    var color: Color { isHealthy ? .ok : .alert }

    var help: String {
        let running = state == .pollerDown ? "is not running" : "is running"
        let last = age.map { "last cycle \(Age.short($0)) ago" } ?? "no cycle recorded"
        return "\(Self.label) \(running) · \(last) · \(queueDepth) job\(queueDepth == 1 ? "" : "s") queued"
    }

    // MARK: - Reading

    /// What the poller wrote. Snake case on purpose: it is the file's schema,
    /// not ours, and a CodingKeys block for five fields is ceremony.
    struct Payload: Decodable {
        let ts: Double
        let poll_interval_secs: Double
        let last_poll_ok: Bool
        let queue_depth: Int
        let oldest_queued_age_secs: Double
        let last_error: String?
    }

    /// nil when this Mac has no bridge at all — no agent and no file. Perch
    /// ships to machines that never had one, and "Bridge: poller down" on a
    /// machine with no poller is a fault report about nothing.
    static func read(agents: [LaunchAgent]) -> BridgeStatus? {
        let agent = agents.first { $0.label == label }
        let payload = (try? Data(contentsOf: file))
            .flatMap { try? JSONDecoder().decode(Payload.self, from: $0) }
        guard agent != nil || payload != nil else { return nil }
        return evaluate(pollerRunning: agent?.isRunning ?? false, payload: payload, now: .now)
    }

    static func evaluate(pollerRunning: Bool, payload: Payload?, now: Date) -> BridgeStatus {
        guard let payload else {
            return BridgeStatus(state: pollerRunning ? .pollFailing : .pollerDown,
                                age: nil, queueDepth: 0)
        }

        let age = now.timeIntervalSince1970 - payload.ts
        // Three cycles: one missed write is a slow GitHub call, three is a lane
        // that has stopped.
        let stale = age > 3 * payload.poll_interval_secs

        let state: State
        if !pollerRunning {
            state = .pollerDown
        } else if stale || !payload.last_poll_ok {
            state = .pollFailing
        } else if payload.oldest_queued_age_secs > queueStuckAfter {
            state = .queueStuck
        } else if payload.last_error?.contains("vault push") == true {
            state = .vaultBroken
        } else {
            state = .alive
        }
        return BridgeStatus(state: state, age: max(0, age), queueDepth: payload.queue_depth)
    }

    #if DEBUG
    static func selfCheck() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func payload(ts: Double = 1_000_000, ok: Bool = true, depth: Int = 0,
                     oldest: Double = 0, error: String? = nil) -> Payload {
            Payload(ts: ts, poll_interval_secs: 60, last_poll_ok: ok, queue_depth: depth,
                    oldest_queued_age_secs: oldest, last_error: error)
        }
        func state(_ running: Bool, _ p: Payload?) -> State {
            evaluate(pollerRunning: running, payload: p, now: now).state
        }

        assert(state(true, payload()) == .alive)
        assert(state(false, payload()) == .pollerDown, "launchd is checked before the file")
        assert(state(true, nil) == .pollFailing, "a running poller that has never written is failing")
        assert(state(false, nil) == .pollerDown)
        assert(state(true, payload(ts: 1_000_000 - 200)) == .pollFailing, "200s is past 3x60")
        assert(state(true, payload(ts: 1_000_000 - 100)) == .alive, "100s is within 3x60")
        assert(state(true, payload(ok: false)) == .pollFailing)
        assert(state(true, payload(depth: 3, oldest: 900)) == .queueStuck)
        assert(state(true, payload(depth: 3, oldest: 60)) == .alive, "a fresh queue is not stuck")
        assert(state(true, payload(error: "vault push failed")) == .vaultBroken)
        assert(state(true, payload(oldest: 900, error: "vault push failed")) == .queueStuck,
               "the stuck queue is the deeper failure and wins")
    }
    #endif
}
