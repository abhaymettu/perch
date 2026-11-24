import SwiftUI

/// Send to: which message target a send key reaches. The whole row is the
/// control, like No Sleep's: a click moves to the next target. The names on
/// the right are the picture of the choice, never colour alone: the chosen
/// one sits in a solid ink chip in heavier type, the line under the title
/// names it in words.
struct SendToRow: View {
    let targets: MessageTargets

    var body: some View {
        Button(action: next) {
            HStack(spacing: 10) {
                Image(systemName: "paperplane")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.ink)
                    .frame(width: 20)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Send to")
                        .font(.rowTitle)
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        detail(now: context.date)
                            .font(.rowMeta)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: 8)

                if targets.targets.count > 1 {
                    TargetChips(names: targets.targets.map(\.name), selected: targets.selected)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PanelRowButtonStyle())
        .disabled(targets.targets.count < 2)
        .help(help)
        .accessibilityRepresentation {
            Picker("Send to", selection: Binding(
                get: { targets.selected ?? "" },
                set: { targets.select($0) }
            )) {
                ForEach(targets.targets.map(\.name), id: \.self) { Text($0).tag($0) }
            }
        }
    }

    private func next() {
        let names = targets.targets.map(\.name)
        guard names.count > 1 else { return }
        let at = targets.selected.flatMap { names.firstIndex(of: $0) } ?? -1
        targets.select(names[(at + 1) % names.count])
    }

    private var help: String {
        guard let selected = targets.selected else { return "Message targets come from targets.json" }
        return targets.targets.count > 1
            ? "Messages go to \(selected). Click to send to the next target."
            : "Messages go to \(selected)."
    }

    /// The last send, for a while after it happened; otherwise where the next
    /// one will go. A failure stays for an hour, a success for ten minutes.
    @ViewBuilder private func detail(now: Date) -> some View {
        if let problem = targets.problem {
            Label(problem, systemImage: "exclamationmark.triangle")
                .foregroundStyle(Color.alert)
        } else if let last = targets.lastResult, !last.ok, now.timeIntervalSince(last.at) < 3600 {
            Label("Not sent: \(last.detail)", systemImage: "exclamationmark.triangle")
                .foregroundStyle(Color.alert)
        } else if let last = targets.lastResult, now.timeIntervalSince(last.at) < 600 {
            Text("\(last.headline) at \(last.at.formatted(date: .omitted, time: .shortened))")
                .foregroundStyle(Color.inkFaint)
        } else if let selected = targets.selected {
            Text("Messages go to \(selected)")
                .foregroundStyle(Color.inkFaint)
        }
    }
}

/// Every target's name in a row, the chosen one in a solid chip. Three at
/// most; past that only the chosen name shows, with how many there are.
private struct TargetChips: View {
    let names: [String]
    let selected: String?
    @Namespace private var chip
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(shown, id: \.self) { name in
                let on = name == selected
                Text(name)
                    .font(.system(size: 11, weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? Color.panelBase : Color.inkMuted)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(height: 19)
                    .background {
                        if on {
                            Capsule()
                                .fill(Color.meterFill)
                                .matchedGeometryEffect(id: "chip", in: chip)
                        }
                    }
            }
            if names.count > 3 {
                Text("\((selected.flatMap { names.firstIndex(of: $0) } ?? 0) + 1) of \(names.count)")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(Color.inkFaint)
                    .padding(.horizontal, 6)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.meterTrack))
        .overlay(Capsule().strokeBorder(Color.panelStroke, lineWidth: 0.5))
        // Critically damped, no bounce: the chip moves to a state, it is not thrown.
        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 1), value: selected)
        .accessibilityHidden(true)
    }

    private var shown: [String] {
        names.count > 3 ? [selected ?? names[0]] : names
    }
}
