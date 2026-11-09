import Foundation
import CoreGraphics

/// A spring in the two numbers a person can reason about: how long one
/// undamped swing would take, and how much of the swing survives. Damping 1 is
/// critically damped and never overshoots; below 1 it does.
struct Spring: Equatable {
    var response: Double
    var damping: Double

    /// Arrives without overshoot. For anything that should read as deliberate.
    static func smooth(_ response: Double) -> Spring { Spring(response: response, damping: 1) }
    /// A little follow-through. For a head settling after it has moved.
    static func settle(_ response: Double) -> Spring { Spring(response: response, damping: 0.78) }
    /// A visible bounce. For landings.
    static func bouncy(_ response: Double) -> Spring { Spring(response: response, damping: 0.5) }
}

/// One number on a spring. Solved in closed form, so the value after any step
/// is exact: the same action samples to the same curve at 60 or 120 frames a
/// second, and a frame that arrives late lands where it should have been.
struct SpringValue {
    private(set) var value: Double
    private(set) var velocity: Double = 0
    private(set) var target: Double
    private var spring = Spring.smooth(0.3)

    init(_ value: Double) {
        self.value = value
        self.target = value
    }

    /// A new target keeps the current value and velocity, which is what lets
    /// one action cut into another without a seam.
    mutating func aim(at target: Double, spring: Spring) {
        self.target = target
        self.spring = spring
    }

    mutating func snap(to value: Double) {
        self.value = value
        self.target = value
        velocity = 0
    }

    /// Moves value and target together. A full head turn ends 2π away from
    /// where it began, on the same pose.
    mutating func shift(by offset: Double) {
        value += offset
        target += offset
    }

    mutating func advance(by dt: Double) {
        guard dt > 0 else { return }
        let omega = 2 * Double.pi / spring.response
        let zeta = min(spring.damping, 1)
        let offset = value - target

        if zeta >= 1 {
            let b = velocity + omega * offset
            let decay = exp(-omega * dt)
            value = target + (offset + b * dt) * decay
            velocity = (b - omega * (offset + b * dt)) * decay
        } else {
            let damped = omega * (1 - zeta * zeta).squareRoot()
            let b = (velocity + zeta * omega * offset) / damped
            let decay = exp(-zeta * omega * dt)
            let (sine, cosine) = (sin(damped * dt), cos(damped * dt))
            value = target + decay * (offset * cosine + b * sine)
            velocity = decay * ((b * damped - zeta * omega * offset) * cosine
                                - (offset * damped + zeta * omega * b) * sine)
        }
    }

    func isSettled(within tolerance: Double) -> Bool {
        // Velocity is judged over a tenth of a second: slow enough that the
        // next six frames would not carry it out of tolerance.
        abs(value - target) < tolerance && abs(velocity) * 0.1 < tolerance
    }
}

/// The owl's ten springs.
struct OwlRig {
    private var channels: [SpringValue]

    init(_ pose: OwlPose = OwlPose()) {
        channels = OwlPose.Channel.allCases.map { SpringValue(Double(pose[$0])) }
    }

    var pose: OwlPose {
        var pose = OwlPose()
        for channel in OwlPose.Channel.allCases {
            pose[channel] = CGFloat(channels[channel.rawValue].value)
        }
        return pose
    }

    func value(_ channel: OwlPose.Channel) -> CGFloat { CGFloat(channels[channel.rawValue].value) }
    func target(_ channel: OwlPose.Channel) -> CGFloat { CGFloat(channels[channel.rawValue].target) }

    mutating func aim(_ channel: OwlPose.Channel, at target: CGFloat, spring: Spring) {
        var target = Double(target)
        if channel == .turn {
            // Whichever way round is nearer. A head past the halfway mark
            // finishes the turn instead of unwinding it.
            let current = channels[channel.rawValue].value
            target += 2 * .pi * ((current - target) / (2 * .pi)).rounded()
        }
        channels[channel.rawValue].aim(at: target, spring: spring)
    }

    /// Aims the turn a whole number of revolutions past where it is going, for
    /// the one move that goes all the way round.
    mutating func spin(by revolutions: CGFloat, spring: Spring) {
        let turn = OwlPose.Channel.turn.rawValue
        channels[turn].aim(at: channels[turn].target + Double(revolutions) * 2 * .pi, spring: spring)
    }

    mutating func snap(to pose: OwlPose) {
        for channel in OwlPose.Channel.allCases {
            channels[channel.rawValue].snap(to: Double(pose[channel]))
        }
    }

    mutating func advance(by dt: TimeInterval) {
        for index in channels.indices { channels[index].advance(by: dt) }
    }

    var isSettled: Bool {
        OwlPose.Channel.allCases.allSatisfy { channels[$0.rawValue].isSettled(within: Double($0.tolerance)) }
    }

    /// Lands every spring exactly on its target and unwinds whole turns, so
    /// the resting frame is the same bitmap every time. Channels in `moving`
    /// are left to finish on their own.
    mutating func rest(except moving: Set<OwlPose.Channel> = []) {
        for channel in OwlPose.Channel.allCases where !moving.contains(channel) {
            channels[channel.rawValue].snap(to: channels[channel.rawValue].target)
        }
        let turn = OwlPose.Channel.turn.rawValue
        let wholeTurns = (channels[turn].value / (2 * .pi)).rounded()
        channels[turn].shift(by: -wholeTurns * 2 * .pi)
    }
}
