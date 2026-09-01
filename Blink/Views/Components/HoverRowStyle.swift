import SwiftUI

struct HoverRowStyle: ViewModifier {
    static let horizontalPadding: CGFloat = 9

    @Environment(ScrollActivity.self) private var scrollActivity

    @State private var isHovered = false

    let onHoverChanged: ((Bool) -> Void)?

    init(onHoverChanged: ((Bool) -> Void)? = nil) {
        self.onHoverChanged = onHoverChanged
    }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(isHovered ? 0.055 : 0))
            )
            .animation(.easeOut(duration: 0.13), value: isHovered)
            .onHover { hovering in
                if hovering && scrollActivity.isScrolling { return }
                isHovered = hovering
                onHoverChanged?(hovering)
            }
    }
}

extension View {
    func hoverRow(onHoverChanged: ((Bool) -> Void)? = nil) -> some View {
        modifier(HoverRowStyle(onHoverChanged: onHoverChanged))
    }
}
