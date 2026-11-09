import Foundation
import CoreGraphics

/// The week as the menu bar shows it, cut down to what the owl reacts to.
struct MenuBarReading: Equatable {
    /// nil with a single account, where there is nothing to tell apart.
    let account: String?
    let percent: Int
    let severity: String
}

/// Everything the owl knows how to do. Idle behaviours fill time and are
/// picked at random; the rest are reactions, each fired by one real event.
enum OwlRepertoire {
    /// How long the owl sits still between idle behaviours. Never zero: an
    /// icon that is always moving reads as a twitch rather than a bird.
    static let restInterval: ClosedRange<Double> = 2.0...5.0

    /// Weighted so the owl mostly just blinks. A menu bar item that swivels
    /// its head every four seconds is a toy; one that does it now and then is
    /// a bird you happen to catch in the act.
    static func idle(using generator: inout some RandomNumberGenerator) -> OwlAction {
        let side: CGFloat = Bool.random(using: &generator) ? 1 : -1
        switch Double.random(in: 0..<1, using: &generator) {
        case ..<0.34: return blink
        case ..<0.46: return doubleBlink
        case ..<0.66: return glance(toward: side)
        case ..<0.78: return tilt(toward: side)
        case ..<0.88: return parallax(toward: side)
        case ..<0.94: return ruffle
        default:      return swivel(toward: side)
        }
    }

    /// While the pointer is on the owl it is busy looking at it, so it only blinks.
    static func idleWhileWatched(using generator: inout some RandomNumberGenerator) -> OwlAction {
        Double.random(in: 0..<1, using: &generator) < 0.75 ? blink : doubleBlink
    }

    // MARK: - Idle

    static let blink = OwlAction("blink") { $0.blink(0) }

    static let doubleBlink = OwlAction("blink twice") {
        $0.blink(0)
        $0.blink(0.2)
    }

    /// A look to one side and back: the owl checking something you can't see.
    /// The eyes narrow as the head leaves, the way anything with eyelids
    /// blinks into a turn, and the body follows the face a beat late.
    static func glance(toward side: CGFloat) -> OwlAction {
        OwlAction(side > 0 ? "glance right" : "glance left") {
            $0.at(0, .lid, 0.5, .smooth(0.09))
            // Far enough that the near eye fattens and the far one thins to a
            // sliver, close enough that both survive the cull. Past ~0.9 rad
            // a one-eyed owl reads as a bug, not a glance.
            $0.at(0, .turn, 0.78 * side, Spring(response: 0.25, damping: 0.72))
            $0.at(0.04, .lean, 0.6 * side, Spring(response: 0.34, damping: 0.8))
            $0.rest(0.1, .lid, spring: .smooth(0.18))
            $0.rest(0.82, .turn, spring: Spring(response: 0.36, damping: 0.9))
            $0.rest(0.86, .lean, spring: .settle(0.42))
        }
    }

    /// The head tips over on its neck and stays there, considering. It is the
    /// one gesture everyone knows an owl by.
    static func tilt(toward side: CGFloat) -> OwlAction {
        OwlAction(side > 0 ? "tilt right" : "tilt left") {
            $0.at(0, .tilt, 0.24 * side, Spring(response: 0.36, damping: 0.62))
            // Up a touch as it tips, which is also what keeps the low corner on the canvas.
            $0.at(0, .lift, 0.45, .smooth(0.3))
            $0.at(0.08, .lid, 1.05, .smooth(0.22))
            $0.blink(0.62, reopenTo: 1.05)
            $0.rest(1.2, .tilt, spring: Spring(response: 0.42, damping: 0.74))
            $0.rest(1.2, .lid, spring: .smooth(0.3))
            $0.rest(1.26, .lift, spring: .smooth(0.4))
        }
    }

    /// The head slides side to side while the face stays pointed at you. Owls
    /// do this to judge distance: the eyes cannot move in the skull, so the
    /// whole head has to provide the parallax. Turning with the sway would
    /// only be a smaller glance, which is why the turn runs against it.
    static func parallax(toward side: CGFloat) -> OwlAction {
        OwlAction("parallax") {
            let sway = Spring(response: 0.4, damping: 0.86)
            $0.at(0, .lift, -0.5, .smooth(0.3))
            $0.at(0, .lean, 2.5 * side, sway)
            $0.at(0, .turn, -0.2 * side, sway)
            $0.at(0.36, .lean, -2.5 * side, Spring(response: 0.5, damping: 0.86))
            $0.at(0.36, .turn, 0.2 * side, Spring(response: 0.5, damping: 0.86))
            $0.rest(0.82, .lean, .turn, spring: .settle(0.44))
            $0.rest(0.86, .lift, spring: .settle(0.4))
        }
    }

    /// Feathers out, a shake, feathers back. Rare, and over in a second.
    static let ruffle = OwlAction("ruffle") {
        let shake = Spring(response: 0.1, damping: 0.55)
        $0.at(0, .puff, 1.09, Spring(response: 0.2, damping: 0.62))
        $0.at(0, .lid, 0.12, .smooth(0.12))
        for (index, swing) in [0.12, -0.12, 0.1, -0.09, 0.06].enumerated() {
            $0.at(0.08 + Double(index) * 0.075, .tilt, CGFloat(swing), shake)
        }
        $0.rest(0.46, .tilt, spring: .settle(0.24))
        $0.rest(0.5, .puff, spring: Spring(response: 0.46, damping: 0.6))
        $0.rest(0.52, .lid, spring: .smooth(0.26))
    }

    /// All the way round, not most of the way and back. Halfway through, the
    /// turn passes ±π: every eye and the beak cull, and for a few frames the
    /// menu bar shows a plain rounded rectangle. That blank is the back of
    /// the owl's head, and it is why the features are projected onto a
    /// cylinder instead of just sliding sideways.
    static func swivel(toward side: CGFloat, name: String? = nil, rank: OwlAction.Rank = .idle) -> OwlAction {
        OwlAction(name ?? (side > 0 ? "swivel right" : "swivel left"), rank: rank) {
            // A small wind-up the other way, so the turn has somewhere to come from.
            $0.at(0, .turn, -0.17 * side, .smooth(0.17))
            $0.at(0, .lid, 0.6, .smooth(0.12))
            $0.spin(0.14, turns: side, Spring(response: 0.66, damping: 0.8))
            $0.rest(0.5, .lid, spring: .smooth(0.2))
        }
    }

    // MARK: - Reactions

    /// A problem appeared. Eyes wide at once, a flinch, a jump, a landing that
    /// squashes the head. The amber tint arrives through the stance; the
    /// motion only has to make you look.
    static let startle = OwlAction("startle", rank: .urgent) {
        $0.at(0, .lid, OwlPose.wideLid, .smooth(0.07))
        $0.at(0, .squash, 0.86, .smooth(0.09))
        $0.at(0.07, .lift, 2.0, Spring(response: 0.2, damping: 0.74))
        $0.at(0.07, .squash, 1.08, Spring(response: 0.15, damping: 0.8))
        $0.rest(0.22, .lift, spring: Spring(response: 0.26, damping: 0.8))
        $0.at(0.35, .squash, 0.84, .smooth(0.09))
        $0.rest(0.43, .squash, spring: Spring(response: 0.3, damping: 0.42))
        // The eyes stay wide through the jump and relax only once it is over.
        $0.rest(0.7, .lid, spring: .smooth(0.5))
    }

    /// The problem went away. Eyes shut, the head sinks as if breathing out,
    /// then it straightens up again.
    static let relief = OwlAction("relief", rank: .notice) {
        $0.at(0, .lid, -0.2, .smooth(0.18))
        $0.at(0, .squash, 0.93, .smooth(0.34))
        $0.at(0, .nod, 0.12, .smooth(0.34))
        $0.at(0.5, .squash, 1.03, Spring(response: 0.4, damping: 0.7))
        $0.rest(0.55, .lid, spring: .smooth(0.3))
        $0.rest(0.55, .nod, spring: .settle(0.4))
        $0.rest(0.8, .squash, spring: .settle(0.4))
    }

    /// The first reading landed. Heavy lids lift partway, two blinks clear
    /// them, and the owl stretches up before settling to watch.
    static let wake = OwlAction("wake", rank: .notice) {
        $0.at(0, .nod, 0.07, .smooth(0.3))
        $0.at(0, .lid, 0.62, .smooth(0.5))
        $0.blink(0.52, reopenTo: 0.82)
        $0.blink(0.8, reopenTo: 1.12)
        $0.at(0.87, .squash, 1.06, Spring(response: 0.3, damping: 0.7))
        $0.at(0.87, .lift, 0.5, Spring(response: 0.3, damping: 0.8))
        $0.rest(0.87, .nod, spring: .settle(0.36))
        $0.rest(1.2, .lid, spring: .smooth(0.3))
        $0.rest(1.2, .squash, .lift, spring: .settle(0.38))
    }

    /// Nothing left to watch. The lids sag, the owl catches itself once, then
    /// gives in.
    static let dozeOff = OwlAction("doze off", rank: .notice) {
        $0.at(0, .lid, 0.48, .smooth(0.6))
        $0.at(0, .nod, 0.17, .smooth(0.9))
        $0.at(0.62, .lid, 0.92, .smooth(0.14))
        $0.at(0.62, .nod, 0.0, Spring(response: 0.2, damping: 0.8))
        $0.rest(1.0, .lid, .nod, spring: .smooth(0.8))
    }

    /// The percent beside the owl just changed, so it looks at it. The title
    /// sits to the owl's right.
    static let noticeReading = OwlAction("notice the number", rank: .notice) {
        $0.at(0, .lid, 0.55, .smooth(0.09))
        $0.at(0, .turn, 0.76, Spring(response: 0.24, damping: 0.72))
        $0.at(0.03, .lean, 1.0, Spring(response: 0.32, damping: 0.8))
        $0.at(0.1, .lid, 1.1, .smooth(0.16))
        $0.rest(0.8, .turn, spring: Spring(response: 0.36, damping: 0.9))
        $0.rest(0.8, .lid, spring: .smooth(0.3))
        $0.rest(0.84, .lean, spring: .settle(0.42))
    }

    /// The reading crossed into warning. A look at the number, away, then
    /// back at it with wide eyes: the second look is the news.
    static let doubleTake = OwlAction("double take", rank: .notice) {
        $0.at(0, .lid, 0.55, .smooth(0.09))
        $0.at(0, .turn, 0.7, Spring(response: 0.24, damping: 0.72))
        $0.at(0.03, .lean, 0.8, Spring(response: 0.32, damping: 0.8))
        $0.rest(0.1, .lid, spring: .smooth(0.16))
        $0.at(0.42, .turn, 0.12, Spring(response: 0.22, damping: 0.9))
        $0.at(0.42, .lean, 0.1, Spring(response: 0.26, damping: 0.9))
        $0.at(0.62, .turn, 0.8, Spring(response: 0.17, damping: 0.62))
        $0.at(0.62, .lean, 1.2, Spring(response: 0.24, damping: 0.7))
        $0.at(0.62, .lid, OwlPose.wideLid, .smooth(0.08))
        $0.rest(1.5, .turn, spring: Spring(response: 0.4, damping: 0.9))
        $0.rest(1.5, .lid, spring: .smooth(0.4))
        $0.rest(1.54, .lean, spring: .settle(0.44))
    }

    /// The week rolled over and the account is fresh. The eyes arch and the
    /// owl hops twice. Once a week per account, which is what earns it.
    static let cheer = OwlAction("cheer", rank: .notice) {
        let (crouch, spring) = (Spring.smooth(0.09), Spring(response: 0.2, damping: 0.76))
        $0.at(0, .lid, OwlPose.wideLid, .smooth(0.1))
        $0.at(0, .cheek, 1, .smooth(0.16))
        $0.at(0.06, .squash, 0.9, crouch)
        for (hop, lean) in [(0.0, 1.0), (0.36, -1.0)] {
            $0.at(0.14 + hop, .lift, hop == 0 ? 1.6 : 1.25, spring)
            $0.at(0.14 + hop, .squash, 1.06, spring)
            $0.at(0.14 + hop, .tilt, 0.1 * lean, .settle(0.2))
            $0.rest(0.27 + hop, .lift, spring: Spring(response: 0.24, damping: 0.82))
            $0.at(0.4 + hop, .squash, 0.9, crouch)
        }
        $0.rest(0.84, .squash, spring: Spring(response: 0.3, damping: 0.45))
        $0.rest(0.84, .tilt, spring: .settle(0.3))
        $0.rest(1.25, .cheek, .lid, spring: .smooth(0.32))
    }

    /// You clicked it. The head dips under the press, like a key.
    static let press = OwlAction("press", rank: .urgent) {
        $0.at(0, .squash, 0.88, .smooth(0.09))
        $0.rest(0.09, .squash, spring: Spring(response: 0.3, damping: 0.5))
    }

    /// You picked another account for the menu bar. The owl goes all the way
    /// round, and the number changes while its back is turned.
    static let switchAccount = swivel(toward: 1, name: "switch account", rank: .urgent)

    /// What the owl does when the number beside it changes. The week only
    /// ever climbs, so a smaller number means it rolled over.
    static func reaction(from old: MenuBarReading, to new: MenuBarReading) -> OwlAction? {
        guard old.account == new.account, old.percent != new.percent else { return nil }
        if new.percent < old.percent { return cheer }
        return old.severity == "normal" && new.severity != "normal" ? doubleTake : noticeReading
    }

    // MARK: - Catalogue

    /// Every action with the states it plays between: what the bounds check
    /// walks and what the clip renderer films.
    struct Scene {
        let action: OwlAction?
        var before = OwlStance(awake: true)
        var after = OwlStance(awake: true)
        var name: String { action?.name ?? label }
        var label = ""
        /// Seconds of stillness to film after the action has landed.
        var tail: TimeInterval = 0.35
    }

    static let catalogue: [Scene] = [
        Scene(action: blink), Scene(action: doubleBlink),
        Scene(action: glance(toward: -1)), Scene(action: glance(toward: 1)),
        Scene(action: tilt(toward: -1)), Scene(action: tilt(toward: 1)),
        Scene(action: parallax(toward: 1)), Scene(action: ruffle),
        Scene(action: swivel(toward: -1)), Scene(action: swivel(toward: 1)),
        Scene(action: startle, after: OwlStance(awake: true, alert: true)),
        Scene(action: relief, before: OwlStance(awake: true, alert: true)),
        Scene(action: wake, before: OwlStance()),
        Scene(action: dozeOff, after: OwlStance()),
        Scene(action: noticeReading), Scene(action: doubleTake), Scene(action: cheer),
        Scene(action: press, after: OwlStance(awake: true, attending: true), tail: 0.6),
        Scene(action: nil, before: OwlStance(awake: true, attending: true), label: "panel closes", tail: 0.9),
        Scene(action: switchAccount, before: OwlStance(awake: true, attending: true),
              after: OwlStance(awake: true, attending: true)),
        Scene(action: nil, after: OwlStance(awake: true, pointer: CGPoint(x: 1, y: 0.4)),
              label: "pointer arrives", tail: 0.7),
        Scene(action: nil, before: OwlStance(awake: true, pointer: CGPoint(x: -1, y: 0)),
              label: "pointer leaves", tail: 0.9),
    ]

    /// How a change of state travels when no action is carrying it.
    static let stanceSpring = Spring(response: 0.38, damping: 0.8)
    /// Following the pointer: quick enough to feel attached to it.
    static let pointerSpring = Spring(response: 0.2, damping: 0.9)
}

extension OwlRepertoire.Scene {
    /// The poses this scene passes through at a fixed frame rate: a short
    /// stillness, the change of stance and the action, then the tail once
    /// everything has landed.
    func poses(fps: Double, lead: TimeInterval = 0.2) -> [OwlPose] {
        var performer = OwlPerformer(stance: before)
        var poses: [OwlPose] = []
        var landedAt: TimeInterval?
        var started = false

        for frame in 0..<Int(12 * fps) {
            let time = Double(frame) / fps
            if !started, time >= lead {
                started = true
                performer.advance(to: lead)
                let spring = (before.pointer ?? after.pointer) == nil ? OwlRepertoire.stanceSpring : OwlRepertoire.pointerSpring
                performer.setStance(after, spring: spring)
                if let action { performer.play(action) }
            }
            performer.advance(to: time)
            poses.append(performer.pose)

            guard started, performer.isResting else { continue }
            landedAt = landedAt ?? time
            if time - landedAt! >= tail { break }
        }
        return poses
    }
}
