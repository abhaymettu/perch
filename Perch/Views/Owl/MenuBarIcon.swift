import SwiftUI

enum MenuBarIcon {
    static let iconSize: CGFloat = 22

    @MainActor
    static func render(pose: OwlPose, alert: Bool = false) -> NSImage {
        let size = NSSize(width: iconSize, height: iconSize)
        let view = MenuBarOwl(size: iconSize, pose: pose, alert: alert)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0

        guard let cgImage = renderer.cgImage else {
            return NSImage(systemSymbolName: "network", accessibilityDescription: "Perch")!
        }

        let image = NSImage(cgImage: cgImage, size: size)
        // A template image is force-tinted to the menubar's own colour, so
        // the alert red only survives outside template mode.
        image.isTemplate = !alert
        return image
    }
}

private struct MenuBarOwl: View {
    let size: CGFloat
    let pose: OwlPose
    let alert: Bool

    private var scale: CGFloat { size / OwlGeometry.baseSize }

    var body: some View {
        Canvas { context, canvasSize in
            let mid = CGPoint(
                x: canvasSize.width / 2 + pose.lean * scale,
                y: canvasSize.height / 2 + 0.5 - pose.lift * scale
            )

            let resting = OwlGeometry.faceRect(centeredAt: mid, scale: scale)
            // A turned head is narrower, and a landed one is shorter. Both are
            // applied to the silhouette here so every feature below can be
            // positioned against the face the frame actually draws.
            let widthScale = 1 - 0.12 * pow(sin(pose.turn), 2)
            let faceRect = CGRect(
                x: mid.x - resting.width * widthScale / 2,
                y: mid.y - resting.height * pose.squash / 2,
                width: resting.width * widthScale,
                height: resting.height * pose.squash
            )

            let eyeCenterY = faceRect.midY - OwlGeometry.eyeCenterOffsetRatio * scale
            let eyeWidth = OwlGeometry.eyeWidthRatio * scale
            let eyeHeight = max(OwlGeometry.eyeHeightRatio * scale * pose.eyeOpenness,
                                OwlGeometry.minEyeHeightRatio * scale)

            // Every feature rides a vertical cylinder standing inside the head.
            // Its radius is fixed by where the eyes have to land at rest: at
            // azimuth ±α they must sit at ±eyeSpacing, so R = eyeSpacing / sin α.
            // Turning the head is then one rotation of that cylinder, and each
            // feature's x position and width fall straight out of its azimuth —
            // including the far side going behind the head and disappearing,
            // which is what a sideways slide can never do.
            let alpha = OwlGeometry.eyeAzimuth
            let radius = OwlGeometry.eyeSpacingRatio * scale / sin(alpha)

            var punch = Path()

            // The beak sits at azimuth 0, dead centre of the face. It narrows
            // about its own x rather than about the canvas origin, which is
            // what the translate-scale-translate is for.
            let beakX = mid.x + radius * sin(pose.turn)
            if cos(pose.turn) > OwlGeometry.cullCosine {
                let beak = OwlGeometry.beakPath(midX: beakX, eyeCenterY: eyeCenterY, scale: scale)
                punch.addPath(beak.applying(
                    CGAffineTransform(translationX: beakX, y: 0)
                        .scaledBy(x: cos(pose.turn), y: 1)
                        .translatedBy(x: -beakX, y: 0)
                ))
            }

            for sign in [CGFloat(-1), 1] {
                let azimuth = pose.turn + sign * alpha
                let facing = cos(azimuth)
                guard facing > OwlGeometry.cullCosine else { continue }

                // The cylinder is vertical, so a turn foreshortens width only —
                // the eye keeps its full height all the way round.
                let width = eyeWidth * facing / cos(alpha)
                let eyeRect = CGRect(
                    x: mid.x + radius * sin(azimuth) - width / 2,
                    y: eyeCenterY - eyeHeight / 2,
                    width: width,
                    height: eyeHeight
                )
                // Keyed off which eye this *is*, never off where it currently
                // sits: reading the x position flips the brow slice halfway
                // through a turn and the face comes apart.
                punch.addPath(OwlGeometry.eyePath(in: eyeRect, innerIsRight: sign < 0))
            }

            // The features are cut out of the head by an inverse clip rather than
            // an even-odd fill, so the beak wedge and the eyes can overlap the
            // head's own curves without punching each other back in. At the back
            // of the head there is nothing left to cut, and clipping to an empty
            // path is not the same as not clipping.
            if !punch.isEmpty {
                context.clip(to: punch, options: .inverse)
            }
            let tint: Color = alert ? .alert : .black
            context.fill(OwlGeometry.headPath(in: faceRect), with: .color(tint))
        }
        .frame(width: size, height: size)
    }
}
