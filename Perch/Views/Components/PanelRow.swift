import SwiftUI

/// A labelled card, the same shape the main panel's sections use. Settings was
/// four unrelated kinds of thing — two preferences, a permission, a link —
/// stacked in one undifferentiated hairline list.
struct PanelGroup<Content: View>: View {
    let label: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 8.5, weight: .medium))
                    .frame(width: 11)

                Text(label)
                    .font(.sectionLabel)
                    .tracking(1.1)
            }
            .foregroundStyle(Color.inkFaint)
            .padding(.horizontal, HoverRowStyle.horizontalPadding)

            VStack(spacing: 0) { content }
                .panelCard()
        }
    }
}

extension View {
    /// The card behind a group of rows — what makes a section read as one group
    /// rather than five stacked dividers. Shared so a `PanelGroup` on the
    /// Settings page and a section on the main panel cannot drift apart.
    func panelCard() -> some View {
        padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.028))
            )
    }
}

/// One line inside a `PanelGroup`. `glyph` is the affordance: without it
/// "Report an Issue" read as a dead label rather than something you click.
struct PanelRow: View {
    private let title: String
    private let detail: String?
    private let glyph: String?
    private let action: () -> Void

    init(_ title: String, detail: String? = nil, glyph: String? = "chevron.right", action: @escaping () -> Void) {
        self.title = title
        self.detail = detail
        self.glyph = glyph
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title)
                    .font(.rowTitle)
                    .foregroundStyle(Color.ink)

                Spacer(minLength: 0)

                if let detail {
                    Text(detail)
                        .font(.rowMeta)
                        .foregroundStyle(Color.inkMuted)
                }

                if let glyph {
                    Image(systemName: glyph)
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(Color.inkFaint)
                }
            }
            .hoverRow()
        }
        .buttonStyle(.plain)
    }
}

/// Not clickable, so no hover and no glyph — a coloured dot carries the state
/// instead, the same way the header pill does.
struct PanelStatusRow: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 7) {
            Text(title)
                .font(.rowTitle)
                .foregroundStyle(Color.ink)

            Spacer(minLength: 0)

            Circle()
                .fill(Color.ok)
                .frame(width: 5, height: 5)

            Text(detail)
                .font(.rowMeta)
                .foregroundStyle(Color.inkMuted)
        }
        .padding(.horizontal, HoverRowStyle.horizontalPadding)
        .padding(.vertical, 6)
    }
}

struct PanelToggleRow: View {
    private let title: String
    private let caption: String?
    private let isOn: Binding<Bool>

    init(_ title: String, caption: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.caption = caption
        self.isOn = isOn
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.rowTitle)
                    .foregroundStyle(Color.ink)

                if let caption {
                    Text(caption)
                        .font(.rowMeta)
                        .foregroundStyle(Color.inkFaint)
                }
            }

            Spacer(minLength: 8)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(PerchToggleStyle())
        }
        .padding(.horizontal, HoverRowStyle.horizontalPadding)
        .padding(.vertical, 6)
    }
}

/// Between rows inside a card, inset so it separates the text rather than
/// cutting the card in half.
struct PanelRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.05))
            .frame(height: 0.5)
            .padding(.leading, HoverRowStyle.horizontalPadding)
    }
}

struct PanelDivider: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.13), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 0.5)
    }
}

struct PanelPageHeader: View {
    let title: String
    let back: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 9) {
            Button(action: back) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isHovered ? Color.ink : Color.inkMuted)
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(isHovered ? 0.10 : 0.06), in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.07)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }

            Text(title)
                .font(.panelTitle)
                .foregroundStyle(Color.ink)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 11)
        .padding(.bottom, 10)
    }
}
