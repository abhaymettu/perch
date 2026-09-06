import SwiftUI

struct OwlHead: View {
    var size: CGFloat = 18
    var eyeState: EyeState = .open

    enum EyeState {
        case open, halfClosed, closed, wide
    }

    private var scale: CGFloat { size / OwlGeometry.baseSize }
    private var eyeOpenness: CGFloat { OwlGeometry.eyeOpenness(for: eyeState) }

    /// Same glass family as `perchGlassCard`: a translucent fill lit from the
    /// top-left, a rim brighter at the top than the bottom, and a soft cast
    /// shadow — so the owl reads as the same material as the panel it sits in.
    private let faceTopColor = Color.white.opacity(0.22)
    private let faceBottomColor = Color.white.opacity(0.10)
    private let rimTopColor = Color.white.opacity(0.55)
    private let rimBottomColor = Color.white.opacity(0.22)
    private let eyeColor = Color.white.opacity(0.92)

    var body: some View {
        Canvas { context, canvasSize in
            let mid = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let faceRect = OwlGeometry.faceRect(centeredAt: mid, scale: scale)
            let head = OwlGeometry.headPath(in: faceRect)
            let lineWidth = max(1, scale)

            context.drawLayer { layer in
                layer.addFilter(.shadow(color: .black.opacity(0.28), radius: 1.5 * scale, y: 0.75 * scale))
                layer.fill(
                    head,
                    with: .linearGradient(
                        Gradient(colors: [faceTopColor, faceBottomColor]),
                        startPoint: CGPoint(x: faceRect.minX, y: faceRect.minY),
                        endPoint: CGPoint(x: faceRect.maxX, y: faceRect.maxY)
                    )
                )
            }

            context.stroke(
                head,
                with: .linearGradient(
                    Gradient(colors: [rimTopColor, rimBottomColor]),
                    startPoint: CGPoint(x: faceRect.midX, y: faceRect.minY),
                    endPoint: CGPoint(x: faceRect.midX, y: faceRect.maxY)
                ),
                lineWidth: lineWidth
            )

            // A soft specular patch near the top edge, like light catching the
            // curved top of a glass card. Purely additive — no shape change.
            var sheen = Path()
            sheen.addRoundedRect(
                in: CGRect(
                    x: faceRect.minX + faceRect.width * 0.1,
                    y: faceRect.minY + faceRect.height * 0.04,
                    width: faceRect.width * 0.42,
                    height: faceRect.height * 0.3
                ),
                cornerSize: CGSize(width: faceRect.height * 0.15, height: faceRect.height * 0.15)
            )
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: scale * 1.2))
                layer.opacity = 0.6
                layer.fill(sheen, with: .color(.white.opacity(0.45)))
            }

            let eyeCenterY = faceRect.midY - OwlGeometry.eyeCenterOffsetRatio * scale
            let eyeSpacing = OwlGeometry.eyeSpacingRatio * scale
            let eyeWidth = OwlGeometry.eyeWidthRatio * scale
            let fullEyeHeight = OwlGeometry.eyeHeightRatio * scale
            let eyeHeight = max(fullEyeHeight * eyeOpenness, OwlGeometry.minEyeHeightRatio * scale)

            for xOffset in [-eyeSpacing, eyeSpacing] {
                let eyeRect = CGRect(
                    x: mid.x + xOffset - eyeWidth / 2,
                    y: eyeCenterY - eyeHeight / 2,
                    width: eyeWidth,
                    height: eyeHeight
                )

                context.fill(
                    OwlGeometry.eyePath(in: eyeRect, innerIsRight: xOffset < 0),
                    with: .color(eyeColor)
                )
            }

            context.fill(
                OwlGeometry.beakPath(midX: mid.x, eyeCenterY: eyeCenterY, scale: scale),
                with: .color(rimTopColor)
            )
        }
        .frame(width: size, height: size)
    }
}
