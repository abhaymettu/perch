import Foundation
import IOKit

/// No Sleep: the Mac stays awake, lid closed included. It is the system's own
/// switch, the one `pmset -a disablesleep 1` flips, so it outlives Perch and
/// can be changed from a terminal too. Perch never keeps its own copy of the
/// answer: it reads the power manager's, once a second on the title timer and
/// again after every change it asks for.
///
/// An idle-sleep assertion (what `caffeinate` holds) is not enough here: it
/// stops the Mac dozing off, but closing the lid still puts it to sleep.
@Observable
final class NoSleep {
    /// What the power manager says. `nil` only where it cannot be read at all,
    /// and then the switch is not shown.
    private(set) var isOn: Bool?
    /// The state a change is heading for, shown on the switch while it runs.
    private(set) var pending: Bool?
    /// Why the last change did not take, until the next one starts.
    private(set) var problem: String?

    private let frozen: Bool

    init() {
        frozen = false
        isOn = Self.read()
    }

    #if DEBUG
    /// For the preview harness: a fixed state, no reads, no changes.
    init(frozen value: Bool) {
        frozen = true
        isOn = value
    }
    #endif

    /// What the switch shows: where it is going, else where it is.
    var displayed: Bool { pending ?? isOn ?? false }

    /// A registry read, no subprocess: cheap enough for the 1 s title timer.
    /// Only writes when the answer moved, so observers stay quiet.
    func refresh() {
        guard !frozen else { return }
        let now = Self.read()
        if now != isOn { isOn = now }
    }

    /// Without a password first, through `sudo -n`, which works for anyone
    /// with a sudo rule for pmset and fails at once for everyone else. Then
    /// the system's administrator prompt. The state is read back after each
    /// try, never assumed from an exit code.
    @MainActor
    func set(_ on: Bool) async {
        guard !frozen, pending == nil, isOn != nil, isOn != on else { return }
        pending = on
        problem = nil
        defer { pending = nil }

        let value = on ? "1" : "0"
        _ = await Shell.run("/usr/bin/sudo", arguments: ["-n", "/usr/bin/pmset", "-a", "disablesleep", value])
        refresh()
        if isOn == on { return }

        // The prompt is another app's window; the panel would sit over it.
        NotificationCenter.default.post(name: .perchPanelShouldClose, object: nil)
        let verb = on ? "on" : "off"
        let error = await Self.runAsAdministrator("""
            do shell script "/usr/bin/pmset -a disablesleep \(value)" \
            with prompt "Perch needs an administrator to turn No Sleep \(verb)." \
            with administrator privileges
            """)
        refresh()
        guard isOn != on else { return }

        // Cancel is an answer, not a failure: the switch just goes back.
        if error == -128 { return }
        problem = "Could not turn No Sleep \(verb)"
    }

    /// In process, so the prompt names Perch and shows its icon rather than
    /// osascript's. On a thread of its own: the prompt waits on a person, and
    /// the main thread keeps the owl and the title going meanwhile. Returns
    /// the AppleScript error number, nil when the script ran.
    private static func runAsAdministrator(_ source: String) async -> Int? {
        await withCheckedContinuation { continuation in
            Thread.detachNewThread {
                var info: NSDictionary?
                NSAppleScript(source: source)?.executeAndReturnError(&info)
                continuation.resume(returning: info?[NSAppleScript.errorNumber] as? Int)
            }
        }
    }

    // MARK: - The power manager

    /// The root of the power tree. Looked up once; it lives as long as the boot.
    private static let rootDomain: io_registry_entry_t =
        IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))

    /// `SleepDisabled` on the root domain is what `pmset -g` prints as
    /// SleepDisabled. A missing key reads as off, which is how pmset shows it.
    static func read() -> Bool? {
        guard rootDomain != IO_OBJECT_NULL else { return nil }
        guard let value = IORegistryEntryCreateCFProperty(
            rootDomain, "SleepDisabled" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() else { return false }
        return (value as? Bool) ?? ((value as? NSNumber)?.boolValue ?? false)
    }

    #if DEBUG
    /// The registry and pmset must agree, or the switch could show the wrong
    /// state for the very thing it exists to report.
    static func selfCheck() async {
        assert(rootDomain != IO_OBJECT_NULL, "no IOPMrootDomain")
        guard let pmset = await Shell.run("/usr/bin/pmset", arguments: ["-g"]) else { return }
        let line = pmset.split(separator: "\n").first { $0.contains("SleepDisabled") }
        let fromPmset = line.map { $0.trimmingCharacters(in: .whitespaces).hasSuffix("1") } ?? false
        assert(read() == fromPmset, "registry says \(String(describing: read())), pmset says \(fromPmset)")
    }
    #endif
}
