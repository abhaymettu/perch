import SwiftUI

struct WelcomeView: View {
    /// The window controller and the preview harness both need this, and 380
    /// tall left ~150pt of dead centre between the copy and the button.
    static let size = CGSize(width: 320, height: 346)

    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore = false
    @State private var appeared = false
    @State private var step: Int

    /// Same trick as `MenuBarView(page:)`: seeding the step lets the preview
    /// harness render screen two without clicking through a live window.
    init(step: Int = 0) {
        _step = State(initialValue: step)
    }

    var body: some View {
        VStack(spacing: 0) {
            if step == 0 {
                welcomeStep
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            } else {
                accessibilityStep
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .padding(28)
        .overlay(alignment: .bottom) {
            // Two dots, not a version string: on the first screen you are being
            // told how far in you are, and the build number is not that.
            HStack(spacing: 5) {
                ForEach(0..<2, id: \.self) { index in
                    Capsule()
                        .fill(index == step ? Color.accent : Color.white.opacity(0.16))
                        .frame(width: index == step ? 14 : 5, height: 5)
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.7), value: step)
            .padding(.bottom, 14)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        // The stock window was system-light with a white pill button; nothing
        // about it said it belonged to the panel it introduces.
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.panelGround.opacity(0.86))
        }
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                appeared = true
            }
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        StepLayout(
            title: "Perch",
            titleSize: 28,
            caption: "Claude sessions, dev servers, daemons\nand simulators, in one menu bar panel.",
            primary: "Get Started",
            action: { withAnimation(.easeInOut(duration: 0.35)) { step = 1 } }
        ) {
            AnimatedOwlHead(size: 58, event: .active)
        }
    }

    private var accessibilityStep: some View {
        StepLayout(
            title: "One-tap focus",
            titleSize: 20,
            caption: "Click a simulator to focus its window.\nThis needs Accessibility access.",
            primary: "Allow Access",
            action: {
                requestAccessibility()
                dismiss()
            },
            secondary: ("Skip for now", dismiss)
        ) {
            Image(systemName: "iphone")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.accent)
        }
    }

    // MARK: - Helpers

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func dismiss() {
        hasLaunchedBefore = true
        WelcomeWindowController.close()
    }
}

/// Both screens through one geometry. Laid out independently they landed their
/// icon, headline and button at three different heights each, so clicking
/// Get Started shifted the entire screen — the tell that reads as cheap without
/// being nameable. Fixed paddings and a fixed title height pin every element.
private struct StepLayout<Icon: View>: View {
    let title: String
    let titleSize: CGFloat
    let caption: String
    let primary: String
    let action: () -> Void
    var secondary: (String, () -> Void)?
    @ViewBuilder let icon: Icon

    var body: some View {
        VStack(spacing: 0) {
            icon
                .frame(width: 86, height: 86)
                // The head's fill is tuned for 20pt in a menu bar; over a dark
                // ground at 3x that it needs something lit to sit on. Same
                // plinth on both screens, so the slot reads as one slot.
                .background {
                    Circle()
                        .fill(Color.white.opacity(0.07))
                        .overlay(Circle().strokeBorder(Color.accent.opacity(0.35), lineWidth: 1))
                        .shadow(color: Color.accent.opacity(0.30), radius: 18)
                }
                .padding(.top, 18)

            Text(title)
                .font(.system(size: titleSize, weight: titleSize > 24 ? .bold : .semibold))
                .foregroundStyle(Color.ink)
                // A wordmark and a headline are different sizes on purpose; the
                // fixed height is what stops that difference moving the body.
                .frame(height: 36)
                .padding(.top, 10)

            Text(caption)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.inkMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)

            Button(action: action) {
                Text(primary)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.accent, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(HoverScaleButtonStyle())

            // Reserved on both screens, filled on one: 24pt of nothing below a
            // button is invisible, a primary button that jumps 24pt between
            // screens is not.
            // A ZStack, not a bare `if`: an empty branch has no layout
            // footprint at all, so the height reserved below the button
            // collapsed and the button moved anyway.
            ZStack {
                Color.clear
                if let secondary {
                    Button(action: secondary.1) {
                        Text(secondary.0)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Color.inkFaint)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: 24)
            .padding(.bottom, 6)
        }
    }
}

/// The only filled button in the app: it lifts slightly on hover and presses in.
private struct HoverScaleButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(isHovered ? 0.06 : 0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
