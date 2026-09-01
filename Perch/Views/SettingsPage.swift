import SwiftUI

struct SettingsPage: View {
    let back: () -> Void

    @AppStorage("showDesktopHelpers") private var showDesktopHelpers = false
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var failure: String?
    @State private var accessibilityTrusted = Accessibility.isTrusted

    var body: some View {
        VStack(spacing: 0) {
            PanelPageHeader(title: "Settings", back: back)
            PanelDivider()

            VStack(spacing: 10) {
                PanelGroup(label: "GENERAL", icon: "slider.horizontal.3") {
                    PanelToggleRow(
                        "Start at login",
                        caption: "Perch is in the menu bar at boot",
                        isOn: $launchAtLogin
                    )

                    if let failure {
                        Text(failure)
                            .font(.rowMeta)
                            .foregroundStyle(Color.alert)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, HoverRowStyle.horizontalPadding)
                            .padding(.bottom, 4)
                    }

                    PanelRowDivider()

                    // ~15 Electron helpers, all noise. Off unless asked for.
                    PanelToggleRow(
                        "Show Claude Desktop",
                        caption: "Adds its helper processes to the list",
                        isOn: $showDesktopHelpers
                    )
                }

                PanelGroup(label: "PERMISSIONS", icon: "lock.shield") {
                    if accessibilityTrusted {
                        PanelStatusRow(title: "Simulator focus", detail: "Allowed")
                    } else {
                        PanelRow("Simulator focus", detail: "Not allowed") {
                            Accessibility.openSystemSettings()
                        }
                    }
                }

                PanelGroup(label: "HELP", icon: "questionmark.circle") {
                    PanelRow("Report an issue", glyph: "arrow.up.right") {
                        NSWorkspace.shared.open(Perch.issuesURL)
                    }
                }
            }
            .padding(12)

            Spacer(minLength: 0)
        }
        .onChange(of: launchAtLogin) { _, enabled in
            apply(enabled)
        }
        // The page is built fresh each time it opens now, so this is where the
        // system-owned toggles get re-read.
        .onAppear {
            accessibilityTrusted = Accessibility.isTrusted
            launchAtLogin = LoginItem.isEnabled
        }
    }

    private func apply(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            failure = nil
        } catch {
            failure = error.localizedDescription
            launchAtLogin = LoginItem.isEnabled
        }
    }
}
