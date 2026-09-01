import Foundation

enum Shell {
    static func run(
        _ path: String,
        arguments: [String] = [],
        mergingErrors: Bool = false
    ) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = mergingErrors ? pipe : FileHandle.nullDevice

            var env = ProcessInfo.processInfo.environment
            if let xcodePath = [
                "/Applications/Xcode.app/Contents/Developer",
                "/Applications/Xcode-beta.app/Contents/Developer"
            ].first(where: { FileManager.default.fileExists(atPath: $0) }) {
                env["DEVELOPER_DIR"] = xcodePath
            }
            process.environment = env

            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
                return
            }

            // Drain first, then reap. Waiting first deadlocks the moment output
            // fills the 64K pipe buffer — `ps -axo args=` clears that on its own.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            continuation.resume(returning: String(data: data, encoding: .utf8))
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
