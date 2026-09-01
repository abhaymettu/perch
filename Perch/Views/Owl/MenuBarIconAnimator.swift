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
            await play(OwlMotion.random())
        }
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
        var elapsed: TimeInterval = 0

        while elapsed < move.duration {
            guard !Task.isCancelled else { return }

            draw(move.pose(elapsed))
            try? await Task.sleep(for: .seconds(Self.frameInterval))
            elapsed += Self.frameInterval
        }

        guard !Task.isCancelled else { return }
        draw(restingPose)
    }

    private func draw(_ pose: OwlPose) {
        button?.image = MenuBarIcon.render(pose: pose, alert: isAlert)
    }
}
