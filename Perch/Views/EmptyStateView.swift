import SwiftUI

/// Nothing running. Perch's whole job is watching, so the empty state says the
/// watch is still on rather than just showing a blank panel.
struct EmptyStateView: View {
    @State private var floatOffset: CGFloat = 0
    @State private var isSnoozing = false

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                floatingZ(x: 19, y: -13, size: 9, delay: 0)
                floatingZ(x: 26, y: -20, size: 11, delay: 0.7)
                floatingZ(x: 34, y: -28, size: 13, delay: 1.4)

                OwlHead(size: 46, eyeState: .closed, pupilOffset: .zero)
                    .offset(y: floatOffset)
            }
            .frame(height: 58)

            Text("All quiet here")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ink)

            Text("No sessions, servers or simulators running.")
                .font(.system(size: 10.5))
                .foregroundStyle(Color.inkFaint)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                floatOffset = -4
            }
            isSnoozing = true
        }
    }

    /// One repeating animation per z, offset by a delay. The previous version
    /// cancelled its own loop with a timed reset and played exactly once.
    private func floatingZ(x: CGFloat, y: CGFloat, size: CGFloat, delay: Double) -> some View {
        Text("z")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(Color.inkFaint)
            .offset(x: x, y: y)
            .opacity(isSnoozing ? 0 : 0.75)
            .animation(
                .easeOut(duration: 2.1).repeatForever(autoreverses: false).delay(delay),
                value: isSnoozing
            )
    }
}
