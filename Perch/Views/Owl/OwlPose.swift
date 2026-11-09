import CoreGraphics

/// Where the head is on one frame.
///
/// The menu bar glyph is an image handed to an `NSStatusBarButton`, and an
/// image cannot animate itself. So the whole owl is redrawn every frame, and a
/// pose is the input to one of those redraws. Every field is a plain number so
/// that each one can ride its own spring (see `OwlRig`).
struct OwlPose: Equatable {
    /// Yaw, radians. 0 faces you; ±π is the back of the head, where every
    /// feature falls off the cylinder and the glyph is a bare squircle.
    var turn: CGFloat = 0
    /// Pitch, radians. Positive looks down, at whatever hangs under the bar.
    var nod: CGFloat = 0
    /// Roll, radians, about the neck. Positive tips the crown to the right.
    var tilt: CGFloat = 0
    /// Sideways shift of the whole head, in points at the base scale.
    var lean: CGFloat = 0
    /// Upward shift, same units.
    var lift: CGFloat = 0
    /// Vertical scale on the head, anchored where it sits. Under 1 it has
    /// landed on something; over 1 it is stretching up.
    var squash: CGFloat = 1
    /// Uniform scale, anchored the same way. Feathers fluffed out.
    var puff: CGFloat = 1
    /// How far the brow sits above the eye. 0 shut, 1 the resting glare,
    /// `wideLid` round with surprise.
    var lid: CGFloat = 1
    /// The lower lid. 0 is out of the way; 1 pushes the eye into a happy arch.
    var cheek: CGFloat = 0
    /// 0 is the bar's own ink, 1 the amber of a problem.
    var alarm: CGFloat = 0

    static let wideLid: CGFloat = 1.25
    static let dozingLid: CGFloat = 0.35

    /// One spring per field. The order is the storage order in `OwlRig`.
    enum Channel: Int, CaseIterable {
        case turn, nod, tilt, lean, lift, squash, puff, lid, cheek, alarm

        var keyPath: WritableKeyPath<OwlPose, CGFloat> {
            switch self {
            case .turn: \.turn
            case .nod: \.nod
            case .tilt: \.tilt
            case .lean: \.lean
            case .lift: \.lift
            case .squash: \.squash
            case .puff: \.puff
            case .lid: \.lid
            case .cheek: \.cheek
            case .alarm: \.alarm
            }
        }

        /// What counts as arrived, in the channel's own units: about a tenth
        /// of a pixel on the glyph. Tighter than that and the display link
        /// keeps running through a tail nobody can see.
        var tolerance: CGFloat {
            switch self {
            case .turn, .nod, .tilt: 0.006
            case .lean, .lift: 0.05
            case .squash, .puff: 0.0035
            case .lid, .cheek, .alarm: 0.012
            }
        }
    }

    /// Turned far enough away that the eyes and the beak have all gone
    /// behind the head: the frames in which the menu bar shows its back.
    var hidesFace: Bool {
        [turn - OwlGeometry.eyeAzimuth, turn, turn + OwlGeometry.eyeAzimuth]
            .allSatisfy { cos($0) <= OwlGeometry.cullCosine }
    }

    subscript(channel: Channel) -> CGFloat {
        get { self[keyPath: channel.keyPath] }
        set { self[keyPath: channel.keyPath] = newValue }
    }
}

/// What the owl is doing when it is doing nothing. Every action ends by
/// returning to the stance its state implies, never to a fixed pose, so a
/// state that changes mid-action is where the action lands.
struct OwlStance: Equatable {
    /// A live reading to watch. False before the first one and while the
    /// chosen account is signed out, and the eyes sit half shut.
    var awake = false
    /// Something needs dealing with: a critical window or a stale reading.
    var alert = false
    /// The panel is open underneath, so the owl is looking down at it.
    var attending = false
    /// Where the pointer is over the status item, each axis -1...1 from the
    /// owl's centre, or nil when it is elsewhere.
    var pointer: CGPoint?

    var pose: OwlPose {
        var pose = OwlPose()
        pose.alarm = alert ? 1 : 0
        guard awake else {
            pose.lid = OwlPose.dozingLid
            pose.nod = 0.07
            return pose
        }
        if attending {
            pose.nod = 0.2
            pose.lid = 0.86
        } else if let pointer {
            // Owls cannot move their eyes in the skull, so looking at
            // something is the whole head's job.
            pose.turn = pointer.x * 0.62
            pose.lean = pointer.x * 0.5
            pose.nod = pointer.y * 0.1
            pose.lid = 1.07
        }
        return pose
    }
}
