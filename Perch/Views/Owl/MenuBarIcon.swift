import SwiftUI

enum MenuBarIcon {
    static let iconSize: CGFloat = 22

    static let awakeOpenness = OwlGeometry.eyeOpenness(for: .open)
    static let asleepOpenness = OwlGeometry.eyeOpenness(for: .halfClosed)

    @MainActor
    static func render(eyeOpenness: CGFloat, alert: Bool = false) -> NSImage {
        let size = NSSize(width: iconSize, height: iconSize)
        let view = MenuBarOwl(size: iconSize, eyeOpenness: eyeOpenness, alert: alert)

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
    let eyeOpenness: CGFloat
    let alert: Bool

    private var scale: CGFloat { size / OwlGeometry.baseSize }

    var body: some View {
        Canvas { context, canvasSize in
            let mid = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2 + 0.5)
            let faceRect = OwlGeometry.faceRect(centeredAt: mid, scale: scale)

            let eyeCenterY = faceRect.midY - OwlGeometry.eyeCenterOffsetRatio * scale
            let eyeSpacing = OwlGeometry.eyeSpacingRatio * scale
            let eyeWidth = OwlGeometry.eyeWidthRatio * scale
            let fullEyeHeight = OwlGeometry.eyeHeightRatio * scale
            let eyeHeight = max(fullEyeHeight * eyeOpenness, OwlGeometry.minEyeHeightRatio * scale)

            var punch = OwlGeometry.beakPath(midX: mid.x, eyeCenterY: eyeCenterY, scale: scale)
            for xOffset in [-eyeSpacing, eyeSpacing] {
                let eyeRect = CGRect(
                    x: mid.x + xOffset - eyeWidth / 2,
                    y: eyeCenterY - eyeHeight / 2,
                    width: eyeWidth,
                    height: eyeHeight
                )
                punch.addPath(OwlGeometry.eyePath(in: eyeRect, innerIsRight: xOffset < 0))
            }

            // The features are cut out of the head by an inverse clip rather than
            // an even-odd fill, so the beak wedge and the eyes can overlap the
            // head's own curves without punching each other back in.
            context.clip(to: punch, options: .inverse)
            let tint: Color = alert ? .alert : .black
            context.fill(OwlGeometry.headPath(in: faceRect), with: .color(tint))
        }
        .frame(width: size, height: size)
    }
}
