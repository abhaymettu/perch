import AppKit
import SwiftUI

struct FailureBox: View {
    let message: String

    @Environment(AppState.self) private var appState

    @State private var copied = false
    @State private var isHoveringCopy = false
    @State private var textHeight: CGFloat = 0

    private static let radius: CGFloat = 4
    private static let inset: CGFloat = 6
    private static let lineLimit = 3

    private static let lineHeight: CGFloat = {
        let font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
        return ceil(font.ascender - font.descender + font.leading)
    }()

    private var isSingleLine: Bool {
        textHeight > 0 && textHeight < Self.lineHeight * 1.5
    }

    var body: some View {
        HStack(alignment: isSingleLine ? .center : .top, spacing: 6) {
            // The mark makes an error distinct from an ordinary inset note
            // without relying on a red background.
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.alert)
                .frame(width: 12, height: 18)
                .accessibilityLabel("Error")

            Text(headline)
                .font(.system(size: 10.5))
                .foregroundStyle(Color.ink)
                .lineLimit(Self.lineLimit)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: TextHeightKey.self, value: proxy.size.height)
                    }
                }

            copyButton
        }
        .onPreferenceChange(TextHeightKey.self) { textHeight = $0 }
        .padding(Self.inset)
        .background {
            RoundedRectangle(cornerRadius: Self.radius)
                .fill(Color.panelGround)
                .overlay {
                    RoundedRectangle(cornerRadius: Self.radius)
                        .strokeBorder(Color.panelRule, lineWidth: 1)
                }
        }
    }

    private var copyButton: some View {
        Button {
            appState.copyToClipboard(text: message)
            withAnimation(.easeInOut(duration: 0.15)) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeInOut(duration: 0.15)) { copied = false }
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(glyphColor)
                .frame(width: 18, height: 18)
                .background {
                    if isHoveringCopy {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.panelHover)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHoveringCopy = $0 }
        .animation(.easeOut(duration: 0.12), value: isHoveringCopy)
        .help(copied ? "Copied" : "Copy full error")
        .accessibilityLabel(copied ? "Copied" : "Copy full error")
    }

    private var glyphColor: Color {
        if copied { return .ok }
        return isHoveringCopy ? .ink : .inkMuted
    }

    private var headline: String { Self.headline(message) }

    static func headline(_ message: String) -> String {
        let lines = message.components(separatedBy: "\n")

        // Stack frames are indented, so trim before finding where the readable
        // explanation ends. The clipboard still receives the complete message.
        let body = lines.prefix {
            let line = $0.trimmingCharacters(in: .whitespaces)
            return !line.hasPrefix("at ") && !line.hasPrefix("File \"")
        }
        guard !body.isEmpty else { return lines.first ?? message }

        var text = body.joined(separator: "\n")
        if let prefix = text.range(of: #"^Error:\s*"#, options: .regularExpression) {
            text.removeSubrange(prefix)
        }
        return text
    }

    static func selfCheck() {
        assert(headline("Error: listen EADDRINUSE: address already in use :::3000\n    at Server.setupListenHandle (node:net:1817:16)")
               == "listen EADDRINUSE: address already in use :::3000")
        assert(headline("Traceback:\n  File \"a.py\", line 3") == "Traceback:")
        assert(headline("    at Server.foo") == "    at Server.foo")
    }
}

private struct TextHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
