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

    static let glassRule = Color.white.opacity(0.10)
    static let glassWarning = Color(hex: 0xFFD078)

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
    static let rowNumber = Font.system(size: 10.5, weight: .medium).monospacedDigit()
    static let sectionLabel = Font.system(size: 9.5, weight: .semibold)
    static let panelTitle = Font.system(size: 13, weight: .semibold)
    static let statValue = Font.system(size: 18, weight: .semibold).monospacedDigit()
    static let statLabel = Font.system(size: 9, weight: .medium)
    static let statFoot = Font.system(size: 9)
}

// Shared presentation-only primitives live in an existing target source file.
enum PerchMark {
    case healthy, warning, unchecked, working
}

struct PerchStatusMark: View {
    let state: PerchMark

    var body: some View {
        ZStack {
            switch state {
            case .healthy:
                Image(systemName: "checkmark.circle")
                    .resizable()
                    .scaledToFit()
            case .warning:
                Image(systemName: "exclamationmark.triangle")
                    .resizable()
                    .scaledToFit()
            case .working:
                Image(systemName: "clock")
                    .resizable()
                    .scaledToFit()
            case .unchecked:
                Circle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                Rectangle()
                    .frame(width: 5, height: 1)
            }
        }
        .frame(width: 13, height: 13)
        .accessibilityHidden(true)
    }
}

struct PerchStateLabel: View {
    let word: String
    var state: PerchMark = .healthy

    var body: some View {
        HStack(spacing: 4) {
            PerchStatusMark(state: state)
            Text(word)
                .lineLimit(1)
        }
        .font(.system(size: 11))
        .foregroundStyle(state == .warning ? Color.alert : Color.inkMuted)
        .accessibilityElement(children: .combine)
    }
}

struct PerchHairline: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .white.opacity(0.19), location: 0.28),
                .init(color: .white.opacity(0.12), location: 0.72),
                .init(color: .clear, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1)
        .accessibilityHidden(true)
    }
}

private struct PerchGlassCard: ViewModifier {
    var radius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Color(hex: 0x3B4049))
                } else {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .fill(Color(hex: 0x313741).opacity(0.51))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [.white.opacity(0.09), .white.opacity(0.025), .clear],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                PerchHairline()
                    .padding(.horizontal, 9)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.14), radius: 5, x: 0, y: 3)
    }
}

extension View {
    func perchGlassCard(radius: CGFloat = 10) -> some View {
        modifier(PerchGlassCard(radius: radius))
    }
}

struct PerchPlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PerchPlainButtonBody(
            label: configuration.label,
            isPressed: configuration.isPressed
        )
    }
}

private struct PerchPlainButtonBody<Label: View>: View {
    let label: Label
    let isPressed: Bool
    @State private var hovered = false

    var body: some View {
        label
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(isPressed ? 0.12 : (hovered ? 0.07 : 0)))
            }
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
    }
}

/// The visual effect samples behind the NSPanel, rather than blurring only
/// SwiftUI siblings. No window ownership, sizing or event contract is changed.
struct PerchWindowBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = PerchVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
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
        ZStack {
            if reduceTransparency {
                Color(hex: 0x30343C)
            } else {
                PerchWindowBackdrop()
                Color(hex: 0x161B23).opacity(0.34)

                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.11), location: 0),
                        .init(color: .white.opacity(0.025), location: 0.28),
                        .init(color: .clear, location: 0.54),
                        .init(color: .white.opacity(0.045), location: 1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.07),
                        .init(color: .white.opacity(0.015), location: 0.18),
                        .init(color: .white.opacity(0.065), location: 0.24),
                        .init(color: .white.opacity(0.018), location: 0.31),
                        .init(color: .clear, location: 0.43)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}