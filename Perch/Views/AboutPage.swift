import SwiftUI

struct AboutPage: View {
    let back: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PanelPageHeader(title: "About", back: back)
            PanelDivider()

            // Still, not animated: the owl moves in the menu bar, which is where
            // you actually look at it. Here it is a portrait.
            OwlHead(size: 58)
                .owlPlinth()
                .padding(.top, 24)

            Text("Perch")
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

            Text(Perch.version)
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.inkFaint)
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(Color.white.opacity(0.05), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.06)))
                .padding(.top, 10)

            PanelGroup(label: "MADE BY", icon: "hammer") {
                PanelRow("abhaymettu", glyph: "arrow.up.right") {
                    NSWorkspace.shared.open(Perch.authorURL)
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
