import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    // MARK: - Ground

    static let panelGround = Color(hex: 0x131317)

    // MARK: - Ink

    /// Three fixed tiers. `.secondary.opacity(0.45)` scattered across a dozen
    /// files is why nothing read as deliberate.
    static let ink = Color(hex: 0xECECF1)
    static let inkMuted = Color(hex: 0x9A9AA7)
    static let inkFaint = Color(hex: 0x646470)

    // MARK: - Accent and states

    // `accent` is generated from AccentColor.colorset (0xD97757) so system
    // controls — toggles, focus rings — inherit the brand instead of macOS blue.
    static let ok = Color(hex: 0x5CC98F)
    static let warn = Color(hex: 0xE0A458)
    static let alert = Color(hex: 0xF0616F)
    static let xcode = Color(hex: 0x4C9AF5)
}

// MARK: - Type ramp

extension Font {
    /// The name of a thing — a session, a server, a daemon.
    static let rowTitle = Font.system(size: 12.5, weight: .medium)
    /// What kind of thing it is. Never competes with the title.
    static let rowMeta = Font.system(size: 10.5)
    /// Ages, ports, percentages. Monospaced so a row stops twitching as they tick.
    static let rowNumber = Font.system(size: 10.5, weight: .medium, design: .monospaced)

    static let sectionLabel = Font.system(size: 9.5, weight: .semibold)
    static let panelTitle = Font.system(size: 13, weight: .semibold)

    /// The three usage percentages, which are the largest text in the panel
    /// because they are the one number worth reading from across the room.
    static let statValue = Font.system(size: 18, weight: .semibold, design: .rounded)
    static let statLabel = Font.system(size: 9, weight: .semibold)
    static let statFoot = Font.system(size: 9)
}
