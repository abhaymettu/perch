import SwiftUI

/// Where the head is on one frame.
///
/// The menu bar glyph is an `NSImage` handed to an `NSStatusBarButton`, and an
/// image cannot animate itself. So nothing here is a SwiftUI animation: the
/// whole owl is redrawn from scratch sixty times a second, and a pose is the
/// input to one of those redraws.
struct OwlPose {
    /// Radians. 0 faces you; ±π is the back of the head, where every feature
    /// falls off the cylinder and the glyph is a bare squircle.
    var turn: CGFloat = 0
    /// Sideways shift of the whole head, in points at the base scale.
    var lean: CGFloat = 0
    /// Upward shift, same units.
    var lift: CGFloat = 0
    /// Vertical scale on the head. 1 at rest; under 1 it has landed on something.
    var squash: CGFloat = 1
    var eyeOpenness: CGFloat = 1

    /// Awake and looking at you.
    static let resting = OwlPose()
    /// Nothing is running, so the eyes are half shut.
    static let dozing = OwlPose(eyeOpenness: OwlGeometry.eyeOpenness(for: .halfClosed))
}

/// One behaviour: how long it lasts and what the head is doing at any point
/// inside it. Every move starts and ends at rest, so they can be played back to
/// back without a transition between them.
struct OwlMove {
    let duration: TimeInterval
    let pose: (TimeInterval) -> OwlPose
}

enum OwlMotion {
    /// How long the owl sits still between moves. Never zero: an icon that is
    /// always moving reads as a twitch rather than a bird.
    static let restInterval: ClosedRange<Double> = 1.6...4.4

    /// Weighted so the owl mostly just blinks. A menu bar item that swivels its
    /// head every four seconds is a toy; one that does it now and then is a bird
    /// you happen to catch in the act.
    static func random() -> OwlMove {
        switch CGFloat.random(in: 0..<1) {
        case ..<0.45: blink(double: CGFloat.random(in: 0..<1) < 0.3)
        case ..<0.67: peek(toward: coinFlip)
        case ..<0.85: bob()
        default:      swivel(toward: coinFlip)
        }
    }

    private static var coinFlip: CGFloat { Bool.random() ? 1 : -1 }

    // MARK: - Blink

    private static let closeDuration: TimeInterval = 0.07
    private static let holdDuration: TimeInterval = 0.03
    private static let openDuration: TimeInterval = 0.18
    private static let blinkCycle = closeDuration + holdDuration + openDuration

    static func blink(double: Bool) -> OwlMove {
        let gap: TimeInterval = 0.06
        let duration = double ? blinkCycle * 2 + gap : blinkCycle

        return OwlMove(duration: duration) { elapsed in
            let phase = elapsed > blinkCycle + gap ? elapsed - blinkCycle - gap : elapsed
            return OwlPose(eyeOpenness: lid(at: phase))
        }
    }

    /// Shut fast, hold a beat, open slow. A symmetric blink looks mechanical —
    /// the asymmetry is most of what sells it as an eyelid.
    private static func lid(at elapsed: TimeInterval) -> CGFloat {
        if elapsed < closeDuration {
            return 1 - easeIn(CGFloat(elapsed / closeDuration))
        }

        let openingStart = closeDuration + holdDuration
        guard elapsed >= openingStart else { return 0 }

        return easeOut(min(CGFloat((elapsed - openingStart) / openDuration), 1))
    }

    // MARK: - Peek

    /// A glance to one side and back: the owl checking something you can't see.
    /// The hold is what makes it read as looking rather than as a wobble.
    static func peek(toward direction: CGFloat) -> OwlMove {
        let swing: TimeInterval = 0.26
        let hold: TimeInterval = 0.45
        // Far enough that the near eye visibly fattens and the far one thins to
        // a sliver, close enough that both survive the cull. Past ~0.9 rad the
        // far eye vanishes and a one-eyed owl reads as a bug, not a glance.
        let angle: CGFloat = 0.78

        return OwlMove(duration: swing * 2 + hold) { elapsed in
            let turn: CGFloat
            if elapsed < swing {
                turn = angle * easeOut(CGFloat(elapsed / swing))
            } else if elapsed < swing + hold {
                turn = angle
            } else {
                let back = min(CGFloat((elapsed - swing - hold) / swing), 1)
                turn = angle * (1 - easeInOut(back))
            }
            return OwlPose(turn: turn * direction, lean: turn * direction * 0.7)
        }
    }

    // MARK: - Bob

    /// The head slides side to side while the face stays pointed at you. Owls do
    /// this to judge distance: the eyes cannot move in the skull, so the whole
    /// head has to provide the parallax. Turning *with* the sway would only be a
    /// smaller peek, which is why the turn runs against it.
    static func bob() -> OwlMove {
        let duration: TimeInterval = 1.1

        return OwlMove(duration: duration) { elapsed in
            let sway = sin(CGFloat(elapsed / duration) * 2 * .pi)
            return OwlPose(
                turn: -sway * 0.22,
                lean: sway * 2.8,
                lift: -abs(sway) * 0.6
            )
        }
    }

    // MARK: - Swivel

    /// All the way round, not most of the way and back. Halfway through, the
    /// turn passes ±π: every eye and the beak cull, and for about an eighth of a
    /// second the menu bar shows a plain rounded rectangle. That blank frame is
    /// the whole move — it is the back of the owl's head, and it is why the
    /// features are projected onto a cylinder instead of just sliding sideways.
    static func swivel(toward direction: CGFloat) -> OwlMove {
        let sweep: TimeInterval = 1.05
        let hold: TimeInterval = 0.1
        let half = sweep / 2

        return OwlMove(duration: sweep + hold) { elapsed in
            // Cubic rather than quadratic on the way round. Roughly a third of
            // the sweep is angle at which nothing is visible, and easing that
            // hard means the owl crosses it fast — the blank is a beat, not a
            // stall.
            let progress: CGFloat
            if elapsed < half {
                progress = rush(CGFloat(elapsed / half)) * 0.5
            } else if elapsed < half + hold {
                progress = 0.5
            } else {
                let out = min(CGFloat((elapsed - half - hold) / half), 1)
                progress = 0.5 + (1 - rush(1 - out)) * 0.5
            }
            return OwlPose(turn: progress * 2 * .pi * direction)
        }
    }

    // MARK: - Startle

    /// Fired when a problem appears, so it is the one move that means something
    /// rather than filling time. Eyes wide, a small jump, a landing that squashes
    /// the head — then straight back to resting, because the red tint is already
    /// carrying the state and the motion only has to announce the change.
    static func startle() -> OwlMove {
        let duration: TimeInterval = 0.5
        let wide = OwlGeometry.eyeOpenness(for: .wide)

        return OwlMove(duration: duration) { elapsed in
            let progress = CGFloat(elapsed / duration)
            // One decaying arc, not a loop: up, over, down, done.
            let jump = sin(progress * .pi) * (1 - progress)
            return OwlPose(
                lift: jump * 2.4,
                squash: 1 - jump * 0.2,
                // The eyes stay wide through the jump and only relax on the way
                // down. Fading them out linearly from frame one throws away the
                // half of the move where anyone is actually looking.
                eyeOpenness: 1 + (wide - 1) * (1 - rush(progress))
            )
        }
    }

    // MARK: - Easing

    private static func easeIn(_ t: CGFloat) -> CGFloat { t * t }

    /// Harder easeIn, for the two places where a gentle start wastes the frames
    /// that carry the move.
    private static func rush(_ t: CGFloat) -> CGFloat { t * t * t }

    private static func easeOut(_ t: CGFloat) -> CGFloat { 1 - (1 - t) * (1 - t) }

    private static func easeInOut(_ t: CGFloat) -> CGFloat {
        t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }
}
