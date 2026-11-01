import SwiftUI

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
                .font(.system(size: 10, weight: .medium))
                // Retain tint in the API, but destructive actions are not a
                // warning state. Amber belongs to actual problems only.
                .foregroundStyle(isHovered ? Color.ink : Color.inkMuted)
                .frame(width: Self.diameter, height: Self.diameter)
                .background {
                    if isHovered {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.white.opacity(0.08))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

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
                .foregroundStyle(isHovered ? Color.ink : Color.inkMuted)
                .frame(width: 26, height: 24)
                .background {
                    if isHovered {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.white.opacity(0.08))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}