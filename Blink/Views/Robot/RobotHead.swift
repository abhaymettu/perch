import SwiftUI

struct RobotHead: View {
    var size: CGFloat = 18
    var eyeState: EyeState = .open
    var pupilOffset: CGPoint = .zero

    enum EyeState {
        case open, halfClosed, closed, wide
    }

    private var scale: CGFloat { size / RobotGeometry.baseSize }
    private var eyeOpenness: CGFloat { RobotGeometry.eyeOpenness(for: eyeState) }

    /// A 0.28 fill with no edge left the head a smudge that the eyes floated
    /// on. The stroke is what gives it a silhouette at 20pt.
    private let faceColor = Color.white.opacity(0.13)
    private let faceEdgeColor = Color.white.opacity(0.34)
    private let eyeColor = Color.white.opacity(0.92)

    var body: some View {
        Canvas { context, canvasSize in
            let mid = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

            let faceWidth = RobotGeometry.faceWidthRatio * scale
            let faceHeight = RobotGeometry.faceHeightRatio * scale
            let faceRect = CGRect(
                x: mid.x - faceWidth / 2,
                y: mid.y - faceHeight / 2,
                width: faceWidth,
                height: faceHeight
            )
            let facePath = Path(roundedRect: faceRect, cornerRadius: RobotGeometry.faceCornerRadiusRatio * scale)
            context.fill(facePath, with: .color(faceColor))
            context.stroke(facePath, with: .color(faceEdgeColor), lineWidth: max(1, scale))

            let eyeCenterY = faceRect.midY - RobotGeometry.eyeCenterOffsetRatio * scale + pupilOffset.y * scale
            let eyeSpacing = RobotGeometry.eyeSpacingRatio * scale
            let eyeWidth = RobotGeometry.eyeWidthRatio * scale
            let fullEyeHeight = RobotGeometry.eyeHeightRatio * scale
            let eyeHeight = max(fullEyeHeight * eyeOpenness, RobotGeometry.minEyeHeightRatio * scale)
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
        }
        .frame(width: size, height: size)
    }
}
