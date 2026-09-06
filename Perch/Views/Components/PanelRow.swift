import SwiftUI

struct PanelGroup<Content: View>: View {
    let label: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .medium))
                    .frame(width: 11)

                Text(label)
                    .font(.sectionLabel)
            }
            .foregroundStyle(Color.inkMuted)
            .padding(.horizontal, HoverRowStyle.horizontalPadding)

            VStack(spacing: 0) { content }
                .panelCard()
        }
    }
}

extension View {
    // A shared surface ties preferences and running processes to the same
    // panel without making each row look like a separate floating control.
    func panelCard() -> some View {
        padding(.vertical, 3)
            .background(Color.panelSurface, in: RoundedRectangle(cornerRadius: 5))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color.panelRule, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

struct PanelRow: View {
    private let title: String
    private let detail: String?
    private let glyph: String?
    private let action: () -> Void

    init(
        _ title: String,
        detail: String? = nil,
        glyph: String? = "chevron.right",
        action: @escaping () -> Void
    ) {
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
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.inkMuted)
                }
            }
            .hoverRow()
        }
        .buttonStyle(.plain)
    }
}

struct PanelStatusRow: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 7) {
            Text(title)
                .font(.rowTitle)
                .foregroundStyle(Color.ink)

            Spacer(minLength: 0)

            // The detail owns the verdict; a generic status row cannot safely
            // infer success from the fact that it has text to display.
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
                        .foregroundStyle(Color.inkMuted)
                }
            }

            Spacer(minLength: 8)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(PerchToggleStyle())
                .accessibilityLabel(title)
        }
        .padding(.horizontal, HoverRowStyle.horizontalPadding)
        .padding(.vertical, 6)
    }
}

struct PanelRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.panelRule)
            .frame(height: 1)
            .padding(.horizontal, HoverRowStyle.horizontalPadding)
            .accessibilityHidden(true)
    }
}

struct PanelDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.panelRule)
            .frame(height: 1)
            .padding(.horizontal, 12)
            .accessibilityHidden(true)
    }
}

struct PanelPageHeader: View {
    let title: String
    let back: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: back) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isHovered ? Color.ink : Color.inkMuted)
                    .frame(width: 24, height: 24)
                    .background(
                        isHovered ? Color.panelHover : Color.panelGround,
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .help("Back")
            .accessibilityLabel("Back")

            Text(title)
                .font(.panelTitle)
                .foregroundStyle(Color.ink)

            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
    }
}
