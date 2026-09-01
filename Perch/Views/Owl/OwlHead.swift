import SwiftUI

struct OwlHead: View {
    var size: CGFloat = 18
    var eyeState: EyeState = .open
    var pupilOffset: CGPoint = .zero

    enum EyeState {
        case open, halfClosed, closed, wide
    }

    private var scale: CGFloat { size / OwlGeometry.baseSize }
    private var eyeOpenness: CGFloat { OwlGeometry.eyeOpenness(for: eyeState) }

    /// A 0.28 fill with no edge left the head a smudge that the eyes floated
    /// on. The stroke is what gives it a silhouette at 20pt.
    private let faceColor = Color.white.opacity(0.13)
    private let faceEdgeColor = Color.white.opacity(0.34)
    private let eyeColor = Color.white.opacity(0.92)

    var body: some View {
        Canvas { context, canvasSize in
            let mid = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let faceRect = OwlGeometry.faceRect(centeredAt: mid, scale: scale)
            let head = OwlGeometry.headPath(in: faceRect)
            let lineWidth = max(1, scale)

            context.fill(head, with: .color(faceColor))
            context.stroke(head, with: .color(faceEdgeColor), lineWidth: lineWidth)

            let eyeCenterY = faceRect.midY - OwlGeometry.eyeCenterOffsetRatio * scale + pupilOffset.y * scale
            let eyeSpacing = OwlGeometry.eyeSpacingRatio * scale
            let eyeWidth = OwlGeometry.eyeWidthRatio * scale
            let fullEyeHeight = OwlGeometry.eyeHeightRatio * scale
            let eyeHeight = max(fullEyeHeight * eyeOpenness, OwlGeometry.minEyeHeightRatio * scale)
            let eyeCornerRadius = eyeWidth / 2

            for xOffset in [-eyeSpacing, eyeSpacing] {
                let eyeX = mid.x + xOffset + pupilOffset.x * 0.5 * scale
                let eyeRect = CGRect(
                    x: eyeX - eyeWidth / 2,
                    y: eyeCenterY - eyeHeight / 2,
                    width: eyeWidth,
                    height: eyeHeight
                )

                context.fill(
                    Path(roundedRect: eyeRect, cornerRadius: eyeCornerRadius),
                    with: .color(eyeColor)
                )
            }

            context.fill(
                OwlGeometry.beakPath(midX: mid.x, eyeCenterY: eyeCenterY, scale: scale),
                with: .color(faceEdgeColor)
            )
        }
        .frame(width: size, height: size)
    }
}
