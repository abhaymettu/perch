import AppKit
import SwiftUI

struct ColorBar: View {
    static let gutter: CGFloat = 12

    let color: Color
    var isWorking: Bool = false

    private static func sameColor(_ a: Color, _ b: Color) -> Bool {
        guard let na = NSColor(a).usingColorSpace(.sRGB),
              let nb = NSColor(b).usingColorSpace(.sRGB) else { return false }
        func key(_ c: NSColor) -> (Int, Int, Int) {
            (
                Int((c.redComponent * 255).rounded()),
                Int((c.greenComponent * 255).rounded()),
                Int((c.blueComponent * 255).rounded())
            )
        }
        return key(na) == key(nb)
    }

    private var mark: PerchMark {
        if isWorking { return .working }
        if Self.sameColor(color, .alert) || Self.sameColor(color, .warn) {
            return .warning
        }
        if Self.sameColor(color, .ok) { return .healthy }
        return .unchecked
    }

    private var accessibilityText: String {
        switch mark {
        case .working: return "Working"
        case .warning: return "Needs attention"
        case .healthy: return "Healthy"
        case .unchecked: return ""
        }
    }

    var body: some View {
        // Legacy category colors are deliberately not rendered as accents or
        // reinterpreted as evidence of health.
        PerchStatusMark(state: mark)
            .scaleEffect(0.77)
            .foregroundStyle(mark == .warning ? Color.alert : Color.inkMuted)
            .frame(width: 10, height: 15)
            .padding(.trailing, Self.gutter - 10)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityHidden(mark == .unchecked)
    }
}