import SwiftUI

struct AboutPage: View {
    let back: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PanelPageHeader(title: "About", back: back)
            PanelDivider()

            // The mascot is the whole personality of this app and it was living
            // at 22pt in a header corner. This is the one page with room for it.
            AnimatedRobotHead(size: 58, event: .idle)
                .frame(width: 86, height: 86)
                // The head's fill is tuned for 20pt in a menu bar; over a dark
                // panel at 3x that it needs something lit to sit on.
                .background {
                    Circle()
                        .fill(Color.white.opacity(0.07))
                        .overlay(Circle().strokeBorder(Color.accent.opacity(0.35), lineWidth: 1))
                        .shadow(color: Color.accent.opacity(0.30), radius: 18)
                }
                .padding(.top, 24)

            Text("Blink")
                .font(.system(size: 27, weight: .bold))
                .tracking(0.3)
                .foregroundStyle(Color.ink)
                .padding(.top, 12)

            Text("Everything running on your Mac, in one panel.")
                .font(.rowMeta)
                .foregroundStyle(Color.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
                .padding(.horizontal, 28)

            Text(Blink.version)
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.inkFaint)
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(Color.white.opacity(0.05), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.06)))
                .padding(.top, 10)

            PanelGroup(label: "MADE BY", icon: "hammer") {
                PanelRow("mo.software", glyph: "arrow.up.right") {
                    NSWorkspace.shared.open(Blink.authorURL)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 22)

            Text("MIT licensed")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.inkFaint)
                .padding(.top, 16)
                .padding(.bottom, 14)
        }
        // Fixed paddings rather than Spacers: with a content-sized panel two
        // greedy Spacers collapsed and dropped the wordmark on the licence line.
        .frame(maxWidth: .infinity)
    }
}
