import Foundation
import CoreGraphics

/// One thing the owl does, written as a score: at this moment, send this
/// channel there on this spring. Nothing in a score says how a value moves
/// between cues. The springs do that, which is why any action can start in the
/// middle of any other and carry on from wherever the head happens to be.
struct OwlAction {
    /// Who may cut in on whom. An action replaces the one playing only if it
    /// ranks at least as high, so a blink never talks over a startle.
    enum Rank: Int, Comparable {
        case idle, notice, urgent
        static func < (a: Rank, b: Rank) -> Bool { a.rawValue < b.rawValue }
    }

    struct Cue {
        enum Target: Equatable {
            case to(CGFloat)
            /// Back to whatever the owl's state says it should be doing.
            case rest
            /// Whole turns past rest. Only the head's yaw goes round.
            case spin(CGFloat)
        }

        let time: TimeInterval
        let channel: OwlPose.Channel
        let target: Target
        let spring: Spring
    }

    let name: String
    let rank: Rank
    let cues: [Cue]

    init(_ name: String, rank: Rank = .idle, _ write: (inout Score) -> Void) {
        var score = Score()
        write(&score)
        self.name = name
        self.rank = rank
        // Stable: cues written for the same instant fire in the order written.
        self.cues = score.cues.enumerated()
            .sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }
            .map(\.element)
    }

    /// The pen a score is written with.
    struct Score {
        fileprivate var cues: [Cue] = []

        mutating func at(_ time: TimeInterval, _ channel: OwlPose.Channel, _ value: CGFloat, _ spring: Spring) {
            cues.append(Cue(time: time, channel: channel, target: .to(value), spring: spring))
        }

        mutating func rest(_ time: TimeInterval, _ channels: OwlPose.Channel..., spring: Spring) {
            for channel in channels {
                cues.append(Cue(time: time, channel: channel, target: .rest, spring: spring))
            }
        }

        mutating func spin(_ time: TimeInterval, turns: CGFloat, _ spring: Spring) {
            cues.append(Cue(time: time, channel: .turn, target: .spin(turns), spring: spring))
        }

        /// Shut fast, open slow. A symmetric blink looks mechanical; the
        /// asymmetry is most of what sells it as an eyelid. The target sits
        /// below shut so the lid arrives with speed and stays down for a beat
        /// instead of creeping onto the line.
        mutating func blink(_ time: TimeInterval, reopenTo open: CGFloat? = nil) {
            at(time, .lid, -0.3, .smooth(0.085))
            if let open {
                at(time + 0.07, .lid, open, .smooth(0.2))
            } else {
                rest(time + 0.07, .lid, spring: .smooth(0.2))
            }
        }
    }
}

/// Plays actions on the rig. A value type with its own clock and no AppKit in
/// it: the menu bar drives one from a display link, and the clip renderer
/// drives another from a loop, and both get the same motion.
struct OwlPerformer {
    private(set) var rig: OwlRig
    private(set) var stance: OwlStance
    private(set) var clock: TimeInterval
    private var playing: (action: OwlAction, start: TimeInterval, next: Int)?
    /// Channels the action has taken and not yet handed back.
    private var held: Set<OwlPose.Channel> = []

    init(stance: OwlStance = OwlStance(), at time: TimeInterval = 0) {
        self.stance = stance
        self.rig = OwlRig(stance.pose)
        self.clock = time
    }

    var pose: OwlPose { rig.pose }
    var playingRank: OwlAction.Rank? { playing?.action.rank }
    var playingName: String? { playing?.action.name }

    /// Nothing left to draw: no action, every spring home.
    var isResting: Bool { playing == nil && rig.isSettled }

    /// Still inside an action, but nothing is moving until its next cue.
    var isHolding: Bool { playing != nil && rig.isSettled }

    /// The state changed. Channels the action is not using go to the new
    /// stance now; the ones it holds get there when it lets go of them.
    mutating func setStance(_ stance: OwlStance, spring: Spring) {
        guard stance != self.stance else { return }
        self.stance = stance
        let pose = stance.pose
        for channel in OwlPose.Channel.allCases where !held.contains(channel) {
            rig.aim(channel, at: pose[channel], spring: spring)
        }
    }

    /// Goes straight to the stance without travelling there: no action, no
    /// movement. Only the channels in `fading` still ease across, which is how
    /// the amber tint arrives under Reduce Motion.
    mutating func land(on stance: OwlStance, fading: Set<OwlPose.Channel> = []) {
        self.stance = stance
        playing = nil
        held = []
        let pose = stance.pose
        for channel in OwlPose.Channel.allCases {
            rig.aim(channel, at: pose[channel], spring: .smooth(0.3))
        }
        rig.rest(except: fading)
    }

    /// Starts an action at the current clock, over whatever was playing.
    mutating func play(_ action: OwlAction) {
        let pose = stance.pose
        for channel in held {
            rig.aim(channel, at: pose[channel], spring: .settle(0.35))
        }
        held = []
        playing = (action, clock, 0)
        fireDueCues(upTo: clock)
    }

    /// Moves the clock while nothing is happening, so the first frame of the
    /// next action does not try to integrate the nap.
    mutating func resync(to time: TimeInterval) {
        guard isResting else { return }
        clock = time
    }

    mutating func advance(to time: TimeInterval) {
        guard time > clock else { return }
        fireDueCues(upTo: time)
        rig.advance(by: time - clock)
        clock = time

        guard rig.isSettled else { return }
        if let playing, playing.next >= playing.action.cues.count {
            self.playing = nil
            held = []
        }
        if playing == nil { rig.rest() }
    }

    /// Each cue lands at its own time, not at the frame after it, by stepping
    /// the springs to the cue first. That is what keeps a score independent of
    /// the frame rate.
    private mutating func fireDueCues(upTo time: TimeInterval) {
        while let current = playing, current.next < current.action.cues.count {
            let cue = current.action.cues[current.next]
            let due = current.start + cue.time
            guard due <= time else { break }

            if due > clock {
                rig.advance(by: due - clock)
                clock = due
            }
            let rest = stance.pose[cue.channel]
            switch cue.target {
            case .to(let value):
                rig.aim(cue.channel, at: value, spring: cue.spring)
                held.insert(cue.channel)
            case .rest:
                rig.aim(cue.channel, at: rest, spring: cue.spring)
                held.remove(cue.channel)
            case .spin(let turns):
                rig.aim(.turn, at: rest, spring: cue.spring)
                rig.spin(by: turns, spring: cue.spring)
                held.remove(.turn)
            }
            playing?.next += 1
        }
    }
}
