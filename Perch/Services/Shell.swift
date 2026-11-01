import Foundation

enum Shell {
    private static let timeout: TimeInterval = 10

    private static let environment: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        if let xcodePath = [
            "/Applications/Xcode.app/Contents/Developer",
            "/Applications/Xcode-beta.app/Contents/Developer"
        ].first(where: { FileManager.default.fileExists(atPath: $0) }) {
            env["DEVELOPER_DIR"] = xcodePath
        }
        return env
    }()

    static func run(
        _ path: String,
        arguments: [String] = [],
        mergingErrors: Bool = false
    ) async -> String? {
        await withCheckedContinuation { continuation in
            // Off the cooperative pool: the drain below blocks its thread until
            // the child exits, and a scan runs several of these at once.
            DispatchQueue.global(qos: .utility).async { autoreleasepool {
                let process = Process()
                let pipe = Pipe()

                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                process.standardOutput = pipe
                process.standardError = mergingErrors ? pipe : FileHandle.nullDevice
                process.environment = environment

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                // A child that hangs (lsof on a dead network mount) would hold
                // the drain below forever, and with it every later scan.
                let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + Self.timeout, execute: watchdog)

                // Drain first, then reap. Waiting first deadlocks the moment output
                // fills the 64K pipe buffer, `ps -axo args=` clears that on its own.
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                watchdog.cancel()
                continuation.resume(returning: String(data: data, encoding: .utf8))
            } }
        }
    }

    #if DEBUG
    /// 200K of output is past the pipe buffer: this hangs forever if the drain
    /// and the wait are ever swapped back.
    static func selfCheck() async {
        let output = await run("/bin/dd", arguments: ["if=/dev/zero", "bs=1000", "count=200"], mergingErrors: false)
        assert(output?.utf8.count == 200_000, "Shell.run truncated or deadlocked on large output")
    }
    #endif
}
