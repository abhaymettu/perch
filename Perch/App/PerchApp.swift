import SwiftUI

/// The entry point: a `Perch send` or `Perch target` runs as a command and
/// exits before AppKit starts; anything else starts the menu bar app.
@main
enum PerchMain {
    static func main() {
        if let status = PerchCommand.run(CommandLine.arguments) { exit(status) }
        PerchApp.main()
    }
}

struct PerchApp: App {
    @NSApplicationDelegateAdaptor(MenuBarController.self) private var menuBar

    var body: some Scene {
        Settings { EmptyView() }
    }
}
