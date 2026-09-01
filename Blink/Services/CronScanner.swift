import Foundation

struct CronJob: Identifiable, Hashable {
    var id: String { "\(schedule) \(command)" }

    let schedule: String
    let command: String
}

/// Most machines have an empty crontab now that the same work tends to live in
/// a LaunchAgent. The section auto-hides when the list is empty, so it costs
/// nothing to keep for the machines that still use one.
///
/// ponytail: no next-run-time. A cron expression parser is real work for a
/// section that currently renders nothing; add one if jobs come back.
enum CronScanner {

    static func scan() async -> [CronJob] {
        guard let output = await Shell.run("/usr/bin/crontab", arguments: ["-l"]) else { return [] }
        return parse(output)
    }

    static func parse(_ output: String) -> [CronJob] {
        output.split(separator: "\n").compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { return nil }

            // Environment assignments (PATH=..., MAILTO=...) are not jobs.
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count > 5, !fields[0].contains("=") else { return nil }

            let schedule = fields.prefix(5).joined(separator: " ")
            let command = fields.dropFirst(5).joined(separator: " ")
            return CronJob(schedule: schedule, command: command)
        }
    }
}
