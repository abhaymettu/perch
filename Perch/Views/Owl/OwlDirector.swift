import AppKit
import QuartzCore

/// Runs the owl in the menu bar. It owns the one `OwlPerformer`, feeds it the
/// app's state and events, and redraws the status button on a display link
/// for exactly as long as something is moving. At rest there is no link, no
/// timer but the one that will start the next idle behaviour, and no drawing.
@MainActor
final class OwlDirector: NSObject {
    private weak var button: NSStatusBarButton?
    private var performer = OwlPerformer(at: CACurrentMediaTime())
    private var link: CADisplayLink?
    private var idleTimer: Timer?
    private var generator = SystemRandomNumberGenerator()
    private var appearance: NSKeyValueObservation?
    /// Owed to the account switch: runs once the owl's back is turned.
    private var swap: (() -> Void)?
    /// A hold has been drawn, so the frames until its next cue are skipped.
    private var holdIsDrawn = false
    /// Time the owl sat out because the main thread was busy. The first open
    /// of the panel can hold a frame back for most of a second, and a clock
    /// that ran on regardless would resume with the press already over.
    private var stalled: CFTimeInterval = 0
    /// A frame this late is a stall, not a dropped frame or two.
    private static let longestStep: CFTimeInterval = 0.06
    private var trace = FrameTrace()

    static let idleKey = "owlIdles"

    init(button: NSStatusBarButton?) {
        self.button = button
        super.init()
        draw()

        // The glyph is tinted for the bar it sits on, so a bar that changes
        // under a resting owl needs one redraw.
        appearance = button?.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.draw() }
        }
        button?.addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self
        ))
        NotificationCenter.default.addObserver(
            self, selector: #selector(conditionsChanged), name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(conditionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)

        if ProcessInfo.processInfo.environment["PERCH_OWL_DEMO"] != nil {
            isDemo = true
            Task { await demo() }
        }
    }

    // MARK: - State

    /// Awake while there is a live reading to watch.
    func setAwake(_ awake: Bool) {
        guard !isDemo, awake != performer.stance.awake else { return }
        var stance = performer.stance
        stance.awake = awake
        change(to: stance, with: awake ? OwlRepertoire.wake : OwlRepertoire.dozeOff)
    }

    /// The amber owl. It startles as the problem appears rather than merely
    /// changing colour, so a stale reading is something you catch out of the
    /// corner of your eye, and it breathes out when the problem clears.
    func setAlert(_ alert: Bool) {
        guard !isDemo, alert != performer.stance.alert else { return }
        var stance = performer.stance
        stance.alert = alert
        let reaction = alert ? OwlRepertoire.startle : OwlRepertoire.relief
        change(to: stance, with: stance.awake ? reaction : nil)
    }

    /// The panel is open under the owl, so it looks down at it.
    func setAttending(_ attending: Bool) {
        guard !isDemo, attending != performer.stance.attending else { return }
        var stance = performer.stance
        stance.attending = attending
        change(to: stance)
    }

    // MARK: - Events

    func pressed() {
        guard !isDemo else { return }
        play(OwlRepertoire.press)
        // The click opens the panel next, on this same turn of the run loop,
        // and that would hold the pressed frame back until the panel is up.
        // Put it on the glass first.
        guard link != nil else { return }
        draw()
        button?.displayIfNeeded()
        CATransaction.flush()
    }

    /// The number beside the owl moved.
    func readingChanged(from old: MenuBarReading, to new: MenuBarReading) {
        guard !isDemo, performer.stance.awake, let reaction = OwlRepertoire.reaction(from: old, to: new) else { return }
        play(reaction)
    }

    /// Another account was picked. `swap` puts its number in the menu bar, and
    /// runs while the owl's back is turned so the change happens out of sight.
    /// It always runs exactly once, at once if the owl is not going to move.
    func switchAccount(then swap: @escaping () -> Void) {
        settleSwap()
        guard !isDemo, canMove else { return swap() }
        self.swap = swap
        play(OwlRepertoire.switchAccount)
    }

    private func settleSwap() {
        swap?()
        swap = nil
    }

    // MARK: - Pointer

    // The owl follows the pointer across the status item, the way it would
    // follow anything that moved in front of it.
    @objc(mouseEntered:) func mouseEntered(with event: NSEvent) { follow(event) }
    @objc(mouseMoved:) func mouseMoved(with event: NSEvent) { follow(event) }
    @objc(mouseExited:) func mouseExited(with event: NSEvent) { setPointer(nil) }

    private func follow(_ event: NSEvent) {
        guard let button else { return }
        let point = button.convert(event.locationInWindow, from: nil)
        let owl = (button.cell as? NSButtonCell)?.imageRect(forBounds: button.bounds) ?? button.bounds
        let down: CGFloat = button.isFlipped ? 1 : -1
        setPointer(CGPoint(
            x: min(max((point.x - owl.midX) / (owl.width * 0.8), -1), 1),
            y: min(max(down * (point.y - owl.midY) / (button.bounds.height / 2), -1), 1)
        ))
    }

    private func setPointer(_ pointer: CGPoint?) {
        var stance = performer.stance
        stance.pointer = canMove ? pointer : nil
        guard !isDemo, stance != performer.stance else { return }
        change(to: stance, spring: pointer == nil ? OwlRepertoire.stanceSpring : OwlRepertoire.pointerSpring)
    }

    // MARK: - Playing

    /// Movement is skipped under Reduce Motion and whenever nobody can see the
    /// menu bar (a full-screen app, an auto-hidden bar, a sleeping display),
    /// where each frame is a wakeup spent on nothing.
    private var canMove: Bool {
        !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && isVisible
    }

    private var isVisible: Bool {
        button?.window?.occlusionState.contains(.visible) == true || Self.benchAssumesVisible
    }

    /// `Scripts/bench.py` hides the status item so a run never shows up in
    /// the menu bar, and needs the owl to idle anyway to measure what it costs.
    private static let benchAssumesVisible = ProcessInfo.processInfo.environment["PERCH_BENCH_OWL_VISIBLE"] != nil

    private func change(to stance: OwlStance, with action: OwlAction? = nil, spring: Spring = OwlRepertoire.stanceSpring) {
        catchUp()
        guard canMove else {
            // The state still has to show. The pose jumps to it; the tint,
            // which is colour and not movement, fades while anyone can see it.
            settleSwap()
            performer.land(on: stance, fading: isVisible ? [.alarm] : [])
            trace.label = "landed"
            return run()
        }
        performer.setStance(stance, spring: spring)
        if let action {
            play(action)
        } else {
            if link == nil { trace.label = "stance" }
            run()
        }
    }

    private func play(_ action: OwlAction) {
        guard canMove else { return settleSwap() }
        if let playing = performer.playingRank, playing > action.rank { return }
        catchUp()
        if action.name != OwlRepertoire.switchAccount.name { settleSwap() }
        performer.play(action)
        trace.label = action.name
        run()
        pace()
    }

    /// Brings the performer's clock to now before anything new is asked of
    /// it. After a rest that is a jump; mid-flight it is one small step.
    private func catchUp() {
        let now = CACurrentMediaTime() - stalled
        performer.resync(to: now)
        performer.advance(to: now)
    }

    private func run() {
        idleTimer?.invalidate()
        idleTimer = nil
        guard link == nil else { return }

        // The button's own link follows it from display to display and only
        // ticks while it is on screen. The bench hides the status item, so
        // there it borrows a screen's link instead.
        let onScreen = button?.window?.occlusionState.contains(.visible) == true
        let link = onScreen
            ? button?.displayLink(target: self, selector: #selector(step))
            : (NSScreen.main ?? NSScreen.screens.first)?.displayLink(target: self, selector: #selector(step))
        guard let link else { return finish() }
        trace.source = onScreen ? "view" : "screen"
        link.add(to: .main, forMode: .common)
        self.link = link
        holdIsDrawn = false
        pace()
    }

    /// Idle behaviours are filler and run at 60 frames a second, which is
    /// what they cost before. A reaction is rare and is the thing being
    /// looked at, so it takes every frame the display has.
    private func pace() {
        let filler = performer.playingRank == .idle
        link?.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: filler ? 60 : 120, preferred: filler ? 60 : 120)
    }

    @objc private func step(_ link: CADisplayLink) {
        // Posed for the moment the frame will be on the glass, not the moment
        // it is drawn.
        let entered = CACurrentMediaTime()
        // A late frame or two lands where it should have been, which is what
        // the springs are for. After a real stall the owl picks up where it
        // was instead, one frame on, so the move it was making is still seen.
        let interval = link.targetTimestamp - link.timestamp
        let behind = link.targetTimestamp - stalled - performer.clock
        if behind > Self.longestStep { stalled += behind - interval }
        performer.advance(to: link.targetTimestamp - stalled)

        if swap != nil, performer.pose.hidesFace || performer.playingName != OwlRepertoire.switchAccount.name {
            settleSwap()
        }

        let started = CACurrentMediaTime()
        if !(performer.isHolding && holdIsDrawn) {
            draw()
            holdIsDrawn = performer.isHolding
        }
        trace.note(link, pose: performer.pose, entered: entered, drawTime: CACurrentMediaTime() - started)

        if performer.isResting { finish() }
    }

    private func finish() {
        link?.invalidate()
        link = nil
        stalled = 0
        settleSwap()
        draw()
        trace.flush()
        scheduleIdle()
    }

    private func draw() {
        guard let button else { return }
        // The button's own effectiveAppearance reflects the real menu bar.
        // AppKit resolves it per item, independent of the app's appearance.
        let isDark = button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        button.image = MenuBarIcon.render(pose: performer.pose, isDarkMenuBar: isDark)
    }

    // MARK: - Idling

    /// Idle motion is filler, so it is the first thing to go: when asked, and
    /// whenever the owl is not allowed to move at all.
    private var canIdle: Bool {
        performer.stance.awake && canMove
            && UserDefaults.standard.object(forKey: Self.idleKey) as? Bool ?? true
    }

    private func scheduleIdle() {
        idleTimer?.invalidate()
        idleTimer = nil
        guard !isDemo, canIdle else { return }

        let timer = Timer(timeInterval: .random(in: OwlRepertoire.restInterval), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.idle() }
        }
        // Nobody is timing the owl. Let the system fold this wakeup into another.
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    private func idle() {
        idleTimer = nil
        guard link == nil, canIdle else { return scheduleIdle() }
        // Busy looking at the pointer or the panel, so it only blinks.
        let stance = performer.stance
        play(stance.pointer == nil && !stance.attending
             ? OwlRepertoire.idle(using: &generator)
             : OwlRepertoire.idleWhileWatched(using: &generator))
    }

    /// The menu bar came back into view, or Reduce Motion was switched.
    @objc private func conditionsChanged(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window !== button?.window { return }
        if link == nil, idleTimer == nil { scheduleIdle() }
    }

    // MARK: - Demo

    private var isDemo = false

    /// `PERCH_OWL_DEMO=1` plays the whole catalogue in the real menu bar, one
    /// scene after another, which is how the weekly cheer gets filmed without
    /// waiting a week. The app's own state is ignored while it runs.
    private func demo() async {
        try? await Task.sleep(for: .seconds(2))
        for scene in OwlRepertoire.catalogue {
            performer.land(on: scene.before)
            draw()
            try? await Task.sleep(for: .seconds(0.7))
            catchUp()
            performer.setStance(scene.after, spring: (scene.before.pointer ?? scene.after.pointer) == nil
                                ? OwlRepertoire.stanceSpring : OwlRepertoire.pointerSpring)
            if let action = scene.action { performer.play(action) }
            trace.label = scene.name
            run()
            while link != nil { try? await Task.sleep(for: .milliseconds(50)) }
            try? await Task.sleep(for: .seconds(0.7))
        }
        if ProcessInfo.processInfo.environment["PERCH_OWL_DEMO"] == "once" { NSApp.terminate(nil) }
        isDemo = false
        scheduleIdle()
    }
}

/// `PERCH_OWL_TRACE=<file>` appends one JSON line per stretch of animation:
/// how many frames it drew and at what rate, the longest gap between two of
/// them, how many gaps were a frame missing, how late the main thread got to
/// a frame, and what drawing cost. It is how "no dropped frames" gets
/// measured on the real menu bar instead of assumed.
private struct FrameTrace {
    var label = ""
    /// Whose display link drove the stretch: the status button's or a screen's.
    var source = ""
    private let path = ProcessInfo.processInfo.environment["PERCH_OWL_TRACE"]
    private var last: CFTimeInterval?
    private var gaps: [Double] = []
    private var draws: [Double] = []
    private var lag: Double = 0
    private var first: OwlPose?
    /// Anything but the tint changed. Under Reduce Motion nothing may.
    private var moved = false

    /// The slowest the link is ever asked to run is 60 a second, so a gap of
    /// more than a frame and a half at that rate is a frame nobody drew.
    private static let missing = 1.5 / 60

    mutating func note(_ link: CADisplayLink, pose: OwlPose, entered: CFTimeInterval, drawTime: CFTimeInterval) {
        guard path != nil else { return }
        var still = pose
        still.alarm = 0
        if let first { moved = moved || still != first } else { first = still }
        if let last { gaps.append(link.timestamp - last) }
        last = link.timestamp
        // A link that skips a tick with the main thread free is the display
        // pacing itself. One that arrives long after its tick was kept waiting.
        lag = max(lag, entered - link.timestamp)
        draws.append(drawTime)
    }

    mutating func flush() {
        defer { (last, gaps, draws, lag, first, moved) = (nil, [], [], 0, nil, false) }
        guard let path, !gaps.isEmpty else { return }
        let sorted = draws.sorted()
        func ms(_ seconds: Double) -> Double { (seconds * 1000 * 100).rounded() / 100 }
        let line: [String: Any] = [
            "action": label,
            "link": source,
            "moved": moved,
            "frames": draws.count,
            "fps": (Double(gaps.count) / gaps.reduce(0, +) * 10).rounded() / 10,
            "max_gap_ms": ms(gaps.max()!),
            "missing_frames": gaps.filter { $0 > Self.missing }.count,
            "main_thread_lag_ms_max": ms(lag),
            "draw_ms_median": ms(sorted[sorted.count / 2]),
            "draw_ms_max": ms(sorted.last!),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]),
              let handle = FileHandle(forWritingAtPath: path) ?? {
                  FileManager.default.createFile(atPath: path, contents: nil)
                  return FileHandle(forWritingAtPath: path)
              }() else { return }
        handle.seekToEndOfFile()
        handle.write(data + Data("\n".utf8))
        try? handle.close()
    }
}
