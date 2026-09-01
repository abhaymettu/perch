import SwiftUI

extension View {
    /// A transition, not an opacity toggle. Keeping all three pages alive and
    /// hiding two of them meant the panel was always as tall as the tallest —
    /// which is what made a two-row panel 640pt of empty black.
    func panelPage(offset: CGFloat) -> some View {
        transition(.opacity.combined(with: .offset(x: offset)))
    }
}

/// Page changes have to be animated at the call site now that the pages come
/// and go, so the panel's height animates with the cross-fade.
let panelPageChange = Animation.snappy(duration: 0.22)
