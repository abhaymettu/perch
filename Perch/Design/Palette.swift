import AppKit
import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    // Opaque surfaces keep the instrument legible regardless of the wallpaper.
    static let panelGround = adaptive("ground", light: 0xF5F1E9, dark: 0x29241F)
    static let panelSurface = adaptive("surface", light: 0xFCF9F3, dark: 0x322C26)
    static let panelHover = adaptive("hover", light: 0xEAE3D8, dark: 0x41382F)
    static let panelRule = adaptive("rule", light: 0xD8CFC2, dark: 0x574B40)

    // Even the quietest text needs enough contrast to carry a small label.
    static let ink = adaptive("ink", light: 0x302A24, dark: 0xF3ECE2)
    static let inkMuted = adaptive("muted", light: 0x655B50, dark: 0xC7BAAA)
    static let inkFaint = adaptive("faint", light: 0x75695C, dark: 0xB1A18E)

    // The asset-catalog accent still supplies the tint for system controls.
    static let terracotta = Color(hex: 0xD97757)
    static let ok = adaptive("ok", light: 0x41644B, dark: 0xA4C4A0)
    static let warn = adaptive("warn", light: 0x865B16, dark: 0xE4BA72)
    static let alert = adaptive("alert", light: 0xA33F30, dark: 0xF0A18A)
    static let xcode = adaptive("xcode", light: 0x386783, dark: 0x9CBFD0)

    private static func adaptive(_ name: String, light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: NSColor.Name("Perch.\(name)")) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

extension Font {
    static let rowTitle = Font.system(size: 12.5, weight: .medium)
    static let rowMeta = Font.system(size: 10.5)

    // Tabular digits prevent ticking values from moving without changing the
    // voice of the surrounding system type.
    static let rowNumber = Font.system(size: 10.5, weight: .medium).monospacedDigit()

    static let sectionLabel = Font.system(size: 9.5, weight: .semibold)
    static let panelTitle = Font.system(size: 13, weight: .semibold)
    static let statValue = Font.system(size: 18, weight: .semibold).monospacedDigit()
    static let statLabel = Font.system(size: 9, weight: .medium)
    static let statFoot = Font.system(size: 9)
}
