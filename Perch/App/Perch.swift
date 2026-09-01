import Foundation

enum Perch {
    static var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "v\(short)"
    }

    static let repositoryURL = URL(string: "https://github.com/abhaymettu/perch")!
    static let issuesURL = URL(string: "https://github.com/abhaymettu/perch/issues/new")!
    static let authorURL = URL(string: "https://github.com/abhaymettu")!
}
