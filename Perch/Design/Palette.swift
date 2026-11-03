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

    // Keep the existing token surface for preferences, welcome and about.
    static let panelGround = adaptive("ground", light: 0xF2F2F4, dark: 0x30343C)
    static let panelSurface = adaptive("surface", light: 0xFAFAFC, dark: 0x3B4049)
    static let panelHover = adaptive("hover", light: 0xE5E5E9, dark: 0x474D57)
    static let panelRule = adaptive("rule", light: 0xD3D4D9, dark: 0x51565F)

    static let ink = adaptive("ink", light: 0x24262B, dark: 0xF4F4F6)
    static let inkMuted = adaptive("muted", light: 0x555962, dark: 0xBEC1C8)
    static let inkFaint = adaptive("faint", light: 0x646973, dark: 0xB8BDC6)

    // Historical names remain source-compatible. Ordinary actions and healthy
    // states are neutral; only problem tokens are amber.
    static let terracotta = adaptive("accent", light: 0x555B65, dark: 0xD4D7DE)
    static let ok = adaptive("ok", light: 0x4B525D, dark: 0xD3D7DF)
    static let warn = adaptive("warn", light: 0x805600, dark: 0xFFD078)
    static let alert = adaptive("alert", light: 0x805601, dark: 0xFFD079)
    static let xcode = adaptive("xcode", light: 0x555C66, dark: 0xD2D5DC)

    static let glassWarning = Color(hex: 0xFFD078)

    // The popover. Base is what the material settles to, for the cut-out in
    // the menu bar mark; the rest are thin enough to sit on the material.
    static let panelBase = adaptive("base", light: 0xECECEE, dark: 0x2A2C31)
    static let panelStroke = adaptiveAlpha("stroke", light: (0x000000, 0.10), dark: (0xFFFFFF, 0.14))
    static let panelDivider = adaptiveAlpha("divider", light: (0x000000, 0.08), dark: (0xFFFFFF, 0.09))
    static let rowHover = adaptiveAlpha("rowHover", light: (0x000000, 0.045), dark: (0xFFFFFF, 0.06))
    static let rowPress = adaptiveAlpha("rowPress", light: (0x000000, 0.08), dark: (0xFFFFFF, 0.10))
    static let meterTrack = adaptiveAlpha("meterTrack", light: (0x000000, 0.09), dark: (0xFFFFFF, 0.12))
    static let meterFill = adaptive("meterFill", light: 0x3A3D44, dark: 0xE6E7EA)

    private static func adaptive(_ name: String, light: UInt32, dark: UInt32) -> Color {
        adaptiveAlpha(name, light: (light, 1), dark: (dark, 1))
    }

    private static func adaptiveAlpha(_ name: String, light: (UInt32, CGFloat), dark: (UInt32, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: NSColor.Name("Perch.\(name)")) { appearance in
            let (hex, alpha) = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha
            )
        })
    }
}

extension Font {
    static let rowTitle = Font.system(size: 12.5, weight: .medium)
    static let rowMeta = Font.system(size: 10.5)
    static let rowNumber = Font.system(size: 10.5, weight: .medium).monospacedDigit()
    static let sectionLabel = Font.system(size: 9.5, weight: .semibold)
    static let panelTitle = Font.system(size: 13, weight: .semibold)
    static let statValue = Font.system(size: 18, weight: .semibold).monospacedDigit()
    static let statLabel = Font.system(size: 9, weight: .medium)
    static let statFoot = Font.system(size: 9)
}

struct PerchHairline: View {
    var body: some View {
        Rectangle()
            .fill(Color.panelDivider)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// A full-width row that reads as one target: a soft fill on hover, a firmer
/// one while pressed, both instant on the way in and quick on the way out.
struct PanelRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PanelRowBody(label: configuration.label, isPressed: configuration.isPressed)
    }
}

private struct PanelRowBody<Label: View>: View {
    let label: Label
    let isPressed: Bool
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        label
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 11)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isPressed ? Color.rowPress : (hovered ? Color.rowHover : .clear))
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onHover { hovered = $0 }
            .animation(reduceMotion || isPressed || hovered ? nil : .easeOut(duration: 0.15), value: hovered)
    }
}

/// The system popover material, sampled from behind the window, following
/// the system appearance like any other menu bar extra.
struct PerchWindowBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = PerchVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private final class PerchVisualEffectView: NSVisualEffectView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // A transparent hosting background is required for behind-window
        // material. Do not replace the controller's content view or delegate.
        window?.isOpaque = false
        window?.backgroundColor = .clear
        window?.hasShadow = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

struct PerchPanelShell: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if reduceTransparency {
                Color.panelBase
            } else {
                PerchWindowBackdrop()
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
