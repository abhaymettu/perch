import SwiftUI

// The native switch ignores every public accent channel inside an agent
// panel, so the track is drawn rather than tinted.
struct PerchToggleStyle: ToggleStyle {
    // A 50x22 switch with a fat pill knob was the loudest object on a 328pt
    // panel — two of them read as the page's subject rather than its controls.
    private static let trackWidth: CGFloat = 34
    private static let trackHeight: CGFloat = 19
    private static let knobWidth: CGFloat = 15
    private static let knobHeight: CGFloat = 15
    private static let inset: CGFloat = 2

    func makeBody(configuration: Configuration) -> some View {
        let travel = (Self.trackWidth - Self.knobWidth) / 2 - Self.inset

        Button {
            withAnimation(.bouncy(duration: 0.28, extraBounce: 0.05)) {
                configuration.isOn.toggle()
            }
        } label: {
            Capsule()
                .fill(configuration.isOn ? Color.accent : Color.primary.opacity(0.14))
                .frame(width: Self.trackWidth, height: Self.trackHeight)
                .overlay {
                    Capsule()
                        .fill(.white)
                        .frame(width: Self.knobWidth, height: Self.knobHeight)
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 0.5)
                        .offset(x: configuration.isOn ? travel : -travel)
                }
        }
        .buttonStyle(.plain)
    }
}
