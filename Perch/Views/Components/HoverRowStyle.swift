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
            .background {
                if isHovered {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.panelHover)
                }
            }
            .animation(.easeOut(duration: 0.13), value: isHovered)
            .onHover { hovering in
                // Scrolling moves rows under a stationary pointer; that should
                // not expose a different row's destructive actions.
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
