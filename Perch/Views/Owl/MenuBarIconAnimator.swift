import SwiftUI

/// Drives the menu bar glyph. An `NSImage` on a status button cannot animate
/// itself, so a behaviour is a short async loop that hands the button a freshly
/// rendered image every frame and then stops. Between behaviours the owl sits
/// still, which is the difference between a bird and a twitching icon.
@MainActor
final class MenuBarIconAnimator {
    private weak var button: NSStatusBarButton?
    private var loop: Task<Void, Never>?
    private var isAwake: Bool?
    private var isAlert = false
    private var restingPose = OwlPose.dozing

    /// Rendered frames per move variant (and resting pose), tint and menu bar
    /// appearance. A render per frame at 60 fps was most of Perch's idle CPU;
    /// every variant together is a few hundred 44×44 bitmaps, about 3 MB.
    private var frames: [String: [NSImage]] = [:]

    private static let frameInterval: TimeInterval = 1.0 / 60.0

    init(button: NSStatusBarButton?) {
        self.button = button
        setAwake(false)
    }

    /// The red owl. It startles as the problem appears rather than merely
    /// changing colour, so a stale session is something you catch out of the
    /// corner of your eye.
    func setAlert(_ alert: Bool) {
        guard alert != isAlert else { return }
        isAlert = alert

        if alert, isAwake == true {
            interrupt(with: OwlMotion.startle())
        } else {
            draw(restingPose)
        }
    }

    func setAwake(_ awake: Bool) {
        guard awake != isAwake else { return }
        isAwake = awake
        restingPose = awake ? .resting : .dozing

        loop?.cancel()
        loop = nil
        draw(restingPose)

        guard awake else { return }
        loop = Task { [weak self] in await self?.idle() }
    }

    private func idle() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(.random(in: OwlMotion.restInterval)))
            guard !Task.isCancelled else { return }

            // Nobody has touched the Mac in a while, so nobody is watching the
            // owl. Sit still and look back in half a minute instead of playing
            // to an empty room (or a locked screen) all night.
            if Self.secondsSinceInput > Self.awayAfter {
                try? await Task.sleep(for: .seconds(30))
                continue
            }
            await play(OwlMotion.random())
        }
    }

    private static let awayAfter: TimeInterval = 120

    private static var secondsSinceInput: TimeInterval {
        // ~0 is kCGAnyInputEventType: keyboard, mouse, trackpad, tablet.
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    /// Cuts the current rest short so a reaction lands now, then hands the owl
    /// back to its idle behaviours.
    private func interrupt(with move: OwlMove) {
        loop?.cancel()
        loop = Task { [weak self] in
            await self?.play(move)
            await self?.idle()
        }
    }

    private func play(_ move: OwlMove) async {
        let key = "\(move.key) \(isAlert) \(isDarkMenuBar)"
        var cached = frames[key] ?? []
        // A cancelled play still keeps the frames it got through.
        defer { frames[key] = cached }

        var elapsed: TimeInterval = 0
        var index = 0

        while elapsed < move.duration {
            guard !Task.isCancelled else { return }

            if index == cached.count { cached.append(render(move.pose(elapsed))) }
            button?.image = cached[index]
            try? await Task.sleep(for: .seconds(Self.frameInterval))
            elapsed += Self.frameInterval
            index += 1
        }

        guard !Task.isCancelled else { return }
        draw(restingPose)
    }

    /// Only ever a resting pose (awake, dozing), redrawn after every move.
    private func draw(_ pose: OwlPose) {
        let key = "rest \(pose.eyeOpenness) \(isAlert) \(isDarkMenuBar)"
        if frames[key] == nil { frames[key] = [render(pose)] }
        button?.image = frames[key]?.first
    }

    private func render(_ pose: OwlPose) -> NSImage {
        MenuBarIcon.render(pose: pose, alert: isAlert, isDarkMenuBar: isDarkMenuBar)
    }

    // The button's own effectiveAppearance reflects the real menu bar —
    // AppKit already resolves this per-item for template-image tinting,
    // independent of whatever appearance the app's own windows are
    // forced into (Perch forces .darkAqua for its panel). NSApp's own
    // appearance would report the wrong thing here.
    private var isDarkMenuBar: Bool {
        button?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}
