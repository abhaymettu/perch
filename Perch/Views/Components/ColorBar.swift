import AppKit
import SwiftUI

struct ColorBar: View {
    static let gutter: CGFloat = 12

    let color: Color
    var isWorking: Bool = false

    private enum Mark {
        case working, alert, warning, healthy, category
    }

    // Existing rows pass semantic palette colours rather than a state enum.
    // Decode those tokens here so their warning marks also work in grayscale.
    // Other colours identify a framework or category, not a health verdict.
    // SwiftUI Color is not Equatable, so the token decode resolves both sides
    // through NSColor and compares sRGB components. Adaptive pairs never share
    // both appearances, so appearance choice cannot cause a false match.
    private static func sameColor(_ a: Color, _ b: Color) -> Bool {
        guard let na = NSColor(a).usingColorSpace(.sRGB),
              let nb = NSColor(b).usingColorSpace(.sRGB) else { return false }
        func key(_ c: NSColor) -> (Int, Int, Int) {
            (Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
        }
        return key(na) == key(nb)
    }

    private var mark: Mark {
        if isWorking { return .working }
        if Self.sameColor(color, .alert) { return .alert }
        if Self.sameColor(color, .warn) { return .warning }
        if Self.sameColor(color, .ok) { return .healthy }
        return .category
    }

    private var accessibilityText: String {
        switch mark {
        case .working: "Working"
        case .alert: "Needs attention"
        case .warning: "Warning"
        case .healthy: "Healthy"
        case .category: ""
        }
    }

    var body: some View {
        ZStack {
            switch mark {
            case .working:
                Image(systemName: "hourglass")
                    .font(.system(size: 9, weight: .medium))
            case .alert:
                Image(systemName: "xmark.square.fill")
                    .font(.system(size: 9, weight: .semibold))
            case .warning:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9, weight: .semibold))
            case .healthy:
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
            case .category:
                Rectangle()
                    .fill(color)
                    .frame(width: 2, height: 12)
            }
        }
        .foregroundStyle(color)
        .frame(width: 10, height: 15)
        .padding(.trailing, Self.gutter - 10)
        .accessibilityLabel(accessibilityText)
        .accessibilityHidden(mark == .category)
    }
}
