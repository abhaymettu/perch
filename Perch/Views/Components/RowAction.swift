import SwiftUI

/// A row's hover action. The glyph carries it; the disc only appears under the
/// cursor. A permanently-filled grey circle in every row reads as chrome
/// bolted on rather than an affordance that belongs to the row.
struct RowAction: View {
    static let spacing: CGFloat = 2

    private static let diameter: CGFloat = 20

    let symbol: String
    let help: String
    var tint: Color?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isHovered ? (tint ?? .ink) : Color.inkMuted)
                .frame(width: Self.diameter, height: Self.diameter)
                .background {
                    Circle().fill(Color.white.opacity(isHovered ? 0.10 : 0))
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

/// Same shape, one size up, for the panel's bottom strip — where the glyph is
/// the only label and has to survive without a row around it.
struct FooterAction: View {
    let symbol: String
    let help: String
    var hoverTint: Color = .ink
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isHovered ? hoverTint : Color.inkFaint)
                .frame(width: 26, height: 24)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(isHovered ? 0.07 : 0))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}
