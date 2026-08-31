import Foundation
import SwiftUI

struct LaunchAgent: Identifiable, Hashable {
    var id: String { label }

    let label: String
    let pid: Int?
    let lastExitStatus: Int
    let schedule: String?
    let plistPath: String

    var isRunning: Bool { pid != nil }
    /// Negative statuses are signal deaths. SIGTERM and SIGKILL mean something
    /// stopped the agent on purpose — a logout, a `launchctl kickstart -k` —
    /// not that it broke, and counting those pins the robot red forever.
    var hasFailed: Bool { lastExitStatus != 0 && lastExitStatus != -15 && lastExitStatus != -9 }

    var color: Color {
        if hasFailed { return .alert }
        return isRunning ? Color(hex: 0x7FBF6A) : .secondary
    }

    var detail: String {
        if hasFailed { return "exit \(lastExitStatus)" }
        if isRunning { return "running" }
        return schedule ?? "loaded"
    }
}

/// Read-only by design. Abhay's agents include the ones that keep his remote
/// control and brain-babysitter alive; a misfired stop is unrecoverable from
/// a menubar panel, so this section never offers one.
enum LaunchAgentScanner {

    private static let directory = ("~/Library/LaunchAgents" as NSString).expandingTildeInPath

    static func scan() async -> [LaunchAgent] {
        guard let output = await Shell.run("/bin/launchctl", arguments: ["list"]) else { return [] }

        let plists = plistsByLabel()
        guard !plists.isEmpty else { return [] }

        return parse(output)
            .compactMap { entry -> LaunchAgent? in
                guard let path = plists[entry.label] else { return nil }
                return LaunchAgent(
                    label: entry.label,
                    pid: entry.pid,
                    lastExitStatus: entry.status,
                    schedule: schedule(fromPlistAt: path),
                    plistPath: path
                )
            }
            .sorted { lhs, rhs in
                lhs.hasFailed == rhs.hasFailed ? lhs.label < rhs.label : lhs.hasFailed
            }
    }

    // MARK: - launchctl list

    struct Entry: Equatable {
        let pid: Int?
        let status: Int
        let label: String
    }

    static func parse(_ output: String) -> [Entry] {
        output.split(separator: "\n").dropFirst().compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 3 else { return nil }
            guard let status = Int(fields[1]) else { return nil }
            return Entry(pid: Int(fields[0]), status: status, label: String(fields[2]))
        }
    }

    // MARK: - Plists

    private static func plistsByLabel() -> [String: String] {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        var result: [String: String] = [:]

        for file in contents where file.hasSuffix(".plist") {
            let label = String(file.dropLast(".plist".count))
            result[label] = (directory as NSString).appendingPathComponent(file)
        }
        return result
    }

    /// The schedule is what makes this section replace the cron one in
    /// practice — a daemon row with no cadence tells you nothing.
    static func schedule(fromPlistAt path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, format: nil
              ) as? [String: Any] else { return nil }

        if let seconds = plist["StartInterval"] as? Int {
            return "every \(Age.short(TimeInterval(seconds)))"
        }

        if plist["StartCalendarInterval"] != nil {
            return calendarLabel(plist["StartCalendarInterval"])
        }

        if plist["RunAtLoad"] as? Bool == true { return "at load" }
        if plist["KeepAlive"] != nil { return "keep alive" }

        return nil
    }

    private static func calendarLabel(_ value: Any?) -> String {
        // StartCalendarInterval is either one dictionary or an array of them.
        let entries: [[String: Any]]
        if let single = value as? [String: Any] {
            entries = [single]
        } else if let many = value as? [[String: Any]] {
            entries = many
        } else {
            return "scheduled"
        }

        guard entries.count == 1, let entry = entries.first,
              let hour = entry["Hour"] as? Int else {
            return "\(entries.count)x daily"
        }

        let minute = entry["Minute"] as? Int ?? 0
        return String(format: "daily %02d:%02d", hour, minute)
    }
}
