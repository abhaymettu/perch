import SwiftUI

enum MenuBarIcon {
    static let iconSize: CGFloat = 22

    @MainActor
    static func render(pose: OwlPose, alert: Bool = false, isDarkMenuBar: Bool) -> NSImage {
        let size = NSSize(width: iconSize, height: iconSize)
        // Template mode discards RGB and re-tints every pixel to one flat
        // foreground colour, keyed off alpha alone. That collapses the
        // specular rim — drawn as *more* alpha, on purpose — into more of
        // that flat colour: white (a highlight) on a dark bar, but black (a
        // dark cap, backwards) on a light one. Rendering in real colour and
        // picking the body tint from the actual menu bar ourselves keeps the
        // highlight a highlight either way; the translucency survives
        // template mode or not, because the bar itself is the thing that's
        // blurring the desktop, not the image.
        let view = MenuBarOwl(size: iconSize, pose: pose, alert: alert, isDarkMenuBar: isDarkMenuBar)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0

        guard let cgImage = renderer.cgImage else {
            return NSImage(systemSymbolName: "network", accessibilityDescription: "Perch")!
        }

        let image = NSImage(cgImage: cgImage, size: size)
        image.isTemplate = false
        return image
    }
}

private struct MenuBarOwl: View {
    let size: CGFloat
    let pose: OwlPose
    let alert: Bool
    let isDarkMenuBar: Bool

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

            let head = OwlGeometry.headPath(in: faceRect)
            // The body tint has to invert with the bar: light glass reads on
            // a dark bar, dark glass on a light one — the same reason none of
            // the row cards in the panel use a single fixed tint either. The
            // highlight and grounding shadow don't invert with it: a
            // highlight is always lighter than the glass under it and a
            // shadow always darker, so both stay fixed regardless of bar.
            let tint: Color = alert ? .alert : (isDarkMenuBar ? .white : .black)

            // Real glass, not a flat silhouette: colour plus real alpha here
            // is a graduated amount of the live menu bar — already blurred
            // over the desktop by the system material — showing through the
            // body. The bar is already doing the blur; this layer only has
            // to be thin enough to let it read. 0.62/0.42 still painted a
            // solid disc at 22pt — real Control Center chips hold this much
            // less colour even over busy content.
            context.fill(
                head,
                with: .linearGradient(
                    Gradient(colors: [tint.opacity(0.26), tint.opacity(0.14)]),
                    startPoint: CGPoint(x: faceRect.midX, y: faceRect.minY),
                    endPoint: CGPoint(x: faceRect.midX, y: faceRect.maxY)
                )
            )

            // Eyes and beak are no longer a cutout hole into raw background —
            // at this body alpha a hole is just as invisible as the glass
            // around it. Real glyphs on real glass chips (Wi-Fi, Bluetooth)
            // stay solid while only the chip is translucent; drawn opposite
            // the body tint, they hold contrast regardless of what's behind
            // the icon.
            if !punch.isEmpty {
                context.drawLayer { layer in
                    layer.clip(to: head)
                    let eyeTint: Color = isDarkMenuBar ? .black.opacity(0.78) : .white.opacity(0.88)
                    layer.fill(punch, with: .color(eyeTint))
                }
            }

            // Specular edge: a bright rim along the top third only, where light
            // would catch a curved surface.
            context.drawLayer { layer in
                layer.clip(to: Path(CGRect(
                    x: faceRect.minX - scale, y: faceRect.minY - scale,
                    width: faceRect.width + 2 * scale, height: faceRect.height * 0.42
                )))
                layer.stroke(head, with: .color(.white.opacity(0.85)), lineWidth: max(0.75, scale * 0.9))
            }

            // Inner glow beneath the rim, fading toward mid-face — depth without
            // a second hard edge.
            context.drawLayer { layer in
                layer.clip(to: head)
                layer.fill(
                    Path(CGRect(
                        x: faceRect.minX, y: faceRect.minY,
                        width: faceRect.width, height: faceRect.height * 0.55
                    )),
                    with: .linearGradient(
                        Gradient(colors: [Color.white.opacity(0.4), .clear]),
                        startPoint: CGPoint(x: faceRect.midX, y: faceRect.minY),
                        endPoint: CGPoint(x: faceRect.midX, y: faceRect.midY)
                    )
                )
            }

            // Grounding shadow along the bottom rim so the shape still reads as
            // a solid body, not just a haze. Always dark — a shadow that
            // flipped white on a dark bar would read as a second highlight.
            context.drawLayer { layer in
                layer.clip(to: Path(CGRect(
                    x: faceRect.minX - scale, y: faceRect.maxY - faceRect.height * 0.4,
                    width: faceRect.width + 2 * scale, height: faceRect.height * 0.4 + scale
                )))
                layer.stroke(head, with: .color(.black.opacity(0.35)), lineWidth: max(0.75, scale * 0.8))
            }
        }
        .frame(width: size, height: size)
    }
}
