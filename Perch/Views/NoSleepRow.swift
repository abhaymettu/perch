import SwiftUI

/// The No Sleep switch. The whole row is the target, like every other row in
/// the panel; the switch is the picture of the state, not a second control.
/// On is said three ways, none of them colour: the switch's knob, a full cup
/// instead of an empty one, and the line under the title.
struct NoSleepRow: View {
    let noSleep: NoSleep

    var body: some View {
        Button {
            Task { await noSleep.set(!noSleep.displayed) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: noSleep.displayed ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(noSleep.displayed ? Color.ink : Color.inkMuted)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 20)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text("No Sleep")
                        .font(.rowTitle)
                    detail
                        .font(.rowMeta)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                PerchSwitch(isOn: noSleep.displayed)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PanelRowButtonStyle())
        .help(noSleep.displayed
              ? "The Mac stays awake, lid closed too. Click to let it sleep."
              : "Keep the Mac awake, lid closed too.")
        .accessibilityRepresentation {
            Toggle("No Sleep", isOn: Binding(
                get: { noSleep.displayed },
                set: { value in Task { await noSleep.set(value) } }
            ))
        }
    }

    @ViewBuilder private var detail: some View {
        if let pending = noSleep.pending {
            Text(pending ? "Turning on…" : "Turning off…")
                .foregroundStyle(Color.inkFaint)
        } else if let problem = noSleep.problem {
            Label(problem, systemImage: "exclamationmark.triangle")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(Color.alert)
        } else {
            Text(noSleep.displayed ? "Awake, even with the lid closed" : "Sleeps as usual")
                .foregroundStyle(Color.inkFaint)
        }
    }
}

/// A switch in the panel's own ink. AppKit's switch draws its inactive grey
/// in a panel that never activates the app, so on and off looked alike. Here
/// on is a solid ink track with the knob to the right, off a faint track with
/// the knob to the left: the position carries it, the lightness backs it up.
private struct PerchSwitch: View {
    let isOn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? Color.meterFill : Color.meterTrack)
                .overlay(Capsule().strokeBorder(Color.panelStroke, lineWidth: isOn ? 0 : 0.5))
            Circle()
                .fill(isOn ? Color.panelBase : Color.white)
                .shadow(color: .black.opacity(isOn ? 0 : 0.18), radius: 0.75, y: 0.5)
                .frame(width: 11, height: 11)
                .padding(2)
        }
        .frame(width: 26, height: 15)
        // Critically damped, no bounce: it is a state, not a throw.
        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 1), value: isOn)
        .accessibilityHidden(true)
    }
}
