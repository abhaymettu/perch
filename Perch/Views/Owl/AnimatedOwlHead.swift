import SwiftUI

struct AnimatedOwlHead: View {
    var size: CGFloat = 18
    var event: AppState.PerchEvent = .idle

    @State private var pupilOffset: CGPoint = .zero
    @State private var eyeState: OwlHead.EyeState = .open
    @State private var tilt: Double = 0
    @State private var swivel: Double = 0
    @State private var bobOffset: CGFloat = 0
    @State private var squish: CGFloat = 1.0
    @State private var blinkTimer: Timer?
    @State private var driftTimer: Timer?
    @State private var sleepTimer: Timer?

    private static let glanceInterval: ClosedRange<Double> = 1.4...4.2
    private static let saccadeDuration: TimeInterval = 0.09
    private static let headFollowDuration: TimeInterval = 0.55
    private static let recentreChance = 0.45
    private static let swivelChance = 0.22
    private static let doubleBlinkChance = 0.3
    /// How long the panel has to sit on `.idle` before the owl dozes off.
    private static let sleepDelay: TimeInterval = 22

    var body: some View {
        OwlHead(size: size, eyeState: eyeState, pupilOffset: pupilOffset)
            .scaleEffect(x: 1.0, y: squish)
            .rotation3DEffect(.degrees(swivel), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
            .rotationEffect(.degrees(tilt))
            .offset(y: bobOffset)
            .onChange(of: event) { _, newEvent in
                handleEvent(newEvent)
            }
            .onAppear {
                scheduleBlinkTimer()
                scheduleGlance()
                startIdleBob()
                handleEvent(event)
            }
            .onDisappear {
                blinkTimer?.invalidate()
                driftTimer?.invalidate()
                sleepTimer?.invalidate()
            }
    }

    private func handleEvent(_ event: AppState.PerchEvent) {
        // Anything happening wakes the owl; only `.idle` re-arms the doze.
        sleepTimer?.invalidate()

        switch event {
        // Idle used to park the eyes at .halfClosed, and the blink timer skips
        // any eyeState that is already closing — so the owl stopped blinking
        // for exactly as long as nothing was happening, sitting on two flat
        // dashes. Idle is open; the glance and blink loops are what carry it.
        case .idle:
            withAnimation(.easeInOut(duration: 0.4)) {
                eyeState = .open
                tilt = 0
                swivel = 0
            }
            scheduleSleep()

        case .active:
            withAnimation(.easeInOut(duration: 0.2)) {
                eyeState = .open
                tilt = 0
                swivel = 0
            }

        case .scanning:
            scanAnimation()

        case .newDetected:
            // The head snaps round toward whatever just appeared, then settles.
            withAnimation(.spring(response: 0.25, dampingFraction: 0.4)) {
                eyeState = .wide
                squish = 1.15
                swivel = -26
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    squish = 1.0
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeInOut(duration: 0.35)) {
                    eyeState = .open
                    swivel = 0
                }
            }

        case .restarting:
            scanAnimation()

        case .failed:
            withAnimation(.spring(response: 0.18, dampingFraction: 0.35)) {
                eyeState = .wide
                tilt = -9
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) {
                withAnimation(.spring(response: 0.18, dampingFraction: 0.35)) { tilt = 9 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { tilt = 0 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeInOut(duration: 0.25)) { eyeState = .open }
            }

        case .killed:
            withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
                squish = 0.9
            }
            quickBlink()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    squish = 1.0
                }
            }
        }
    }

    private func startIdleBob() {
        withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
            bobOffset = -1.5
        }
    }

    private func scheduleBlinkTimer() {
        blinkTimer?.invalidate()
        blinkTimer = Timer.scheduledTimer(
            withTimeInterval: Double.random(in: OwlBlink.interval),
            repeats: false
        ) { _ in
            if eyeState != .closed && eyeState != .halfClosed {
                quickBlink()
                // Owls often blink twice in quick succession. Always-single
                // reads mechanical, which is the one thing a mascot cannot be.
                if Double.random(in: 0...1) < Self.doubleBlinkChance {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { quickBlink() }
                }
            }
            scheduleBlinkTimer()
        }
    }

    private func scheduleSleep() {
        sleepTimer = Timer.scheduledTimer(withTimeInterval: Self.sleepDelay, repeats: false) { _ in
            withAnimation(.easeInOut(duration: 1.4)) { eyeState = .halfClosed }
        }
    }

    private func scheduleGlance() {
        driftTimer?.invalidate()
        driftTimer = Timer.scheduledTimer(
            withTimeInterval: .random(in: Self.glanceInterval),
            repeats: false
        ) { _ in
            glance()
            scheduleGlance()
        }
    }

    private func glance() {
        // A dozing owl does not dart its eyes around behind shut lids.
        guard eyeState != .halfClosed else { return }

        if Double.random(in: 0...1) < Self.swivelChance {
            headSwivel()
            return
        }

        let target = Double.random(in: 0...1) < Self.recentreChance
            ? .zero
            : CGPoint(x: .random(in: -0.6...0.6), y: .random(in: -0.3...0.3))

        withAnimation(.easeOut(duration: Self.saccadeDuration)) {
            pupilOffset = target
        }

        withAnimation(.easeInOut(duration: Self.headFollowDuration)) {
            tilt = Double(target.x) * 3.0
        }
    }

    /// The owl turn — a head that rotates further than a neck should. It is the
    /// one move everybody reads as an owl, and a Y-axis 3D rotation sells it in
    /// a way a flat horizontal squeeze cannot.
    private func headSwivel() {
        let direction: Double = Bool.random() ? -1 : 1

        withAnimation(.easeInOut(duration: 0.45)) {
            swivel = 54 * direction
            pupilOffset = CGPoint(x: 0.5 * direction, y: 0)
            tilt = 4 * direction
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
            withAnimation(.easeInOut(duration: 0.5)) {
                swivel = 0
                pupilOffset = .zero
                tilt = 0
            }
        }
    }

    private func quickBlink() {
        withAnimation(.easeIn(duration: OwlBlink.closeDuration)) {
            eyeState = .closed
        }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + OwlBlink.closeDuration + OwlBlink.holdDuration
        ) {
            withAnimation(.easeOut(duration: OwlBlink.openDuration)) {
                eyeState = .open
            }
        }
    }

    private func scanAnimation() {
        withAnimation(.easeInOut(duration: 0.35)) {
            pupilOffset = CGPoint(x: -0.8, y: -0.1)
            tilt = -4
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeInOut(duration: 0.35)) {
                pupilOffset = CGPoint(x: 0.8, y: -0.1)
                tilt = 4
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeInOut(duration: 0.25)) {
                pupilOffset = .zero
                tilt = 0
            }
        }
    }
}
