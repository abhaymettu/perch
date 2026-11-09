import AppKit
import SwiftUI

/// Draws the owl. One pose in, one bitmap out, straight into a Core Graphics
/// context: the glyph is 30 by 22 points, and at that size a SwiftUI
/// `ImageRenderer` per frame cost a hundred megabytes to do what forty lines of
/// fills and clips do here.
enum MenuBarIcon {
    static let iconSize: CGFloat = 22
    /// The owl is drawn at `iconSize`; the canvas is wider so its moves have
    /// room. 30 keeps the resting owl on a whole point.
    static let canvasSize = CGSize(width: 30, height: iconSize)

    private static var scale: CGFloat { iconSize / OwlGeometry.baseSize }

    /// The head as it would sit with no lean, lift, squash or puff.
    private static func restingRect(for pose: OwlPose) -> CGRect {
        OwlGeometry.faceRect(
            centeredAt: CGPoint(x: canvasSize.width / 2 + pose.lean * scale,
                                y: canvasSize.height / 2 + 0.5 - pose.lift * scale),
            scale: scale
        )
    }

    /// Where the head sits on one frame, before it tilts. Squash and puff are
    /// anchored at the bottom edge, where the owl meets whatever it is sitting
    /// on, so a landing flattens downward instead of shrinking in mid-air. A
    /// squashed head spreads and a turned one is narrower.
    static func faceRect(for pose: OwlPose) -> CGRect {
        let resting = restingRect(for: pose)
        let height = resting.height * pose.puff * pose.squash
        let width = resting.width * pose.puff * spread(for: pose) * (1 - 0.12 * pow(sin(pose.turn), 2))
        return CGRect(x: resting.midX - width / 2, y: resting.maxY - height, width: width, height: height)
    }

    private static func spread(for pose: OwlPose) -> CGFloat { 1 + (1 - pose.squash) * 0.5 }

    /// The tilt turns the head about its neck, low in the head, so the crown
    /// swings and the chin stays put.
    static func tiltTransform(for pose: OwlPose) -> CGAffineTransform {
        let resting = restingRect(for: pose)
        let neck = CGPoint(x: resting.midX, y: resting.maxY - resting.height * 0.15)
        return CGAffineTransform(translationX: neck.x, y: neck.y)
            .rotated(by: pose.tilt)
            .translatedBy(x: -neck.x, y: -neck.y)
    }

    /// The grounding shadow is stroked on the head's outline, so half of it
    /// lands outside `faceRect`.
    static var shadowWidth: CGFloat { max(0.75, scale * 0.8) }

    /// Everything the frame inks, as a box on the canvas.
    static func inkBounds(for pose: OwlPose) -> CGRect {
        faceRect(for: pose)
            .insetBy(dx: -shadowWidth / 2, dy: -shadowWidth / 2)
            .applying(tiltTransform(for: pose))
    }

    static func render(pose: OwlPose, isDarkMenuBar: Bool) -> NSImage {
        guard let image = bitmap(pose: pose, isDarkMenuBar: isDarkMenuBar) else {
            return NSImage(systemSymbolName: "bird", accessibilityDescription: "Perch")!
        }
        // Not a template: template mode re-tints every pixel to one flat
        // colour keyed off alpha alone, which turns the highlight on the rim
        // into a dark cap on a light bar. Real colour, with the body tint
        // picked from the actual bar, keeps a highlight a highlight.
        let icon = NSImage(cgImage: image, size: canvasSize)
        icon.isTemplate = false
        return icon
    }

    /// `pixelsPerPoint` is 2 for the menu bar; the clip renderer asks for more
    /// to film the owl enlarged without resampling it.
    static func bitmap(pose: OwlPose, isDarkMenuBar: Bool, pixelsPerPoint: CGFloat = 2) -> CGImage? {
        let (width, height) = (Int(canvasSize.width * pixelsPerPoint), Int(canvasSize.height * pixelsPerPoint))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Top-left origin, y down, in points: the coordinates the geometry is written in.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: pixelsPerPoint, y: -pixelsPerPoint)
        draw(pose, isDarkMenuBar: isDarkMenuBar, in: context)
        return context.makeImage()
    }

    private static let amber: [CGFloat] = [1, 208 / 255, 120 / 255]

    private static func draw(_ pose: OwlPose, isDarkMenuBar: Bool, in context: CGContext) {
        let face = faceRect(for: pose)
        let head = OwlGeometry.headPath(in: face).cgPath
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        func color(_ rgb: [CGFloat], _ alpha: CGFloat) -> CGColor {
            CGColor(colorSpace: space, components: rgb + [alpha])!
        }
        func gradient(_ from: CGColor, _ to: CGColor) -> CGGradient {
            CGGradient(colorsSpace: space, colors: [from, to] as CFArray, locations: [0, 1])!
        }
        let white: [CGFloat] = [1, 1, 1]

        context.saveGState()
        context.concatenate(tiltTransform(for: pose))

        // The body tint inverts with the bar: light glass reads on a dark bar,
        // dark glass on a light one. It is thin on purpose. The bar is already
        // blurring the desktop, and this layer only has to let that through.
        // A problem mixes the tint toward amber rather than switching to it,
        // so the colour arrives over a few frames.
        let ink: CGFloat = isDarkMenuBar ? 1 : 0
        let alarm = min(max(pose.alarm, 0), 1)
        let tint = amber.map { ink + ($0 - ink) * alarm }

        context.saveGState()
        context.addPath(head)
        context.clip()
        context.drawLinearGradient(gradient(color(tint, 0.26), color(tint, 0.14)),
                                   start: CGPoint(x: face.midX, y: face.minY),
                                   end: CGPoint(x: face.midX, y: face.maxY), options: [])

        // Eyes and beak are solid shapes on the glass, not holes in it: at
        // this body alpha a hole is as invisible as the glass around it. One
        // layer, so a beak sliding over an eye mid-turn does not double up.
        context.setAlpha(0.55)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setFillColor(color(white, 1))
        for feature in features(for: pose, on: face) {
            context.addPath(feature)
        }
        context.fillPath()
        context.endTransparencyLayer()
        context.setAlpha(1)

        // Inner glow beneath the rim, fading toward mid-face: depth without a
        // second hard edge.
        context.clip(to: CGRect(x: face.minX, y: face.minY, width: face.width, height: face.height * 0.55))
        context.drawLinearGradient(gradient(color(white, 0.4), color(white, 0)),
                                   start: CGPoint(x: face.midX, y: face.minY),
                                   end: CGPoint(x: face.midX, y: face.midY), options: [])
        context.restoreGState()

        // Grounding shadow along the bottom rim so the shape reads as a solid
        // body, not a haze. Always dark: a shadow that flipped white on a dark
        // bar would read as a second highlight.
        context.clip(to: CGRect(x: face.minX - scale, y: face.maxY - face.height * 0.4,
                                width: face.width + 2 * scale, height: face.height * 0.4 + scale))
        context.addPath(head)
        context.setStrokeColor(color([0, 0, 0], 0.35))
        context.setLineWidth(shadowWidth)
        context.strokePath()
        context.restoreGState()
    }

    /// The eyes and the beak for one pose.
    ///
    /// Every feature rides a vertical cylinder standing inside the head. Its
    /// radius is fixed by where the eyes have to land at rest: at azimuth ±α
    /// they must sit at ±eyeSpacing, so R = eyeSpacing / sin α. Turning the
    /// head is then one rotation of that cylinder, and each feature's x
    /// position and width fall out of its azimuth, including the far side
    /// going behind the head and disappearing, which a sideways slide can
    /// never do. A nod rolls the same features down the face.
    private static func features(for pose: OwlPose, on face: CGRect) -> [CGPath] {
        let size = scale * pose.puff
        let alpha = OwlGeometry.eyeAzimuth
        let radius = OwlGeometry.eyeSpacingRatio * size / sin(alpha)
        let stretch = pose.squash
        let drop = radius * sin(pose.nod)
        let eyeCenterY = face.midY + (drop - OwlGeometry.eyeCenterOffsetRatio * size) * stretch
        let midX = face.midX
        var paths: [CGPath] = []

        // The beak sits at azimuth 0, dead centre of the face, and narrows
        // about its own x. It stands proud of the face, so a nod carries it
        // further than the eyes and shows more of its length.
        if cos(pose.turn) > OwlGeometry.cullCosine {
            let beakX = midX + radius * spread(for: pose) * sin(pose.turn)
            let beak = OwlGeometry.beakPath(midX: beakX, eyeCenterY: eyeCenterY + 0.3 * drop * stretch,
                                            scale: size, depthScale: stretch * (1 + 0.35 * sin(pose.nod)))
            paths.append(beak.applying(
                CGAffineTransform(translationX: beakX, y: 0)
                    .scaledBy(x: cos(pose.turn), y: 1)
                    .translatedBy(x: -beakX, y: 0)
            ).cgPath)
        }

        // Surprise makes the eye itself a little bigger, not just rounder.
        let wide = 1 + 0.1 * min(max(pose.lid - 1, 0) / (OwlPose.wideLid - 1), 1)
        let eyeSize = OwlGeometry.eyeWidthRatio * size * wide
        for sign in [CGFloat(-1), 1] {
            let azimuth = pose.turn + sign * alpha
            let facing = cos(azimuth)
            guard facing > OwlGeometry.cullCosine else { continue }

            // The cylinder is vertical, so a turn foreshortens width only.
            let width = eyeSize * facing / cos(alpha)
            // Half the head's squash: enough to belong to it, not enough to
            // turn a round eye into a lozenge.
            let height = eyeSize * (0.5 + 0.5 * stretch)
            let eyeRect = CGRect(
                x: midX + radius * spread(for: pose) * sin(azimuth) - width / 2,
                y: eyeCenterY - height / 2,
                width: width,
                height: height
            )
            // Keyed off which eye this is, never off where it currently sits:
            // reading the x position flips the brow halfway through a turn and
            // the face comes apart.
            paths.append(OwlGeometry.eyePath(in: eyeRect, innerIsRight: sign < 0,
                                             lid: pose.lid, cheek: pose.cheek).cgPath)
        }
        return paths
    }

    #if DEBUG
    /// Every scene in the catalogue, sampled every millisecond: what the frame
    /// inks keeps half a point clear of every canvas edge, because the canvas
    /// cuts off anything drawn past it. Then every frame the menu bar would
    /// draw at 60 a second is rendered, and its outermost pixel ring must be
    /// empty. Each scene must also end resting on the stance it was heading
    /// for, which is what catches a score that forgets to hand a channel back.
    static func selfCheck() {
        let safe = CGRect(origin: .zero, size: canvasSize).insetBy(dx: 0.5, dy: 0.5)
        for scene in OwlRepertoire.catalogue {
            for (ms, pose) in scene.poses(fps: 1000).enumerated() {
                let ink = inkBounds(for: pose)
                assert(safe.contains(ink), "owl \(scene.name) at \(ms)ms: ink \(ink) leaves \(safe)")
            }
            let frames = scene.poses(fps: 60)
            assert(frames.last == scene.after.pose, "owl \(scene.name) ends on \(String(describing: frames.last)), not its stance")
            for (index, pose) in frames.enumerated() {
                let ink = edgeInk(bitmap(pose: pose, isDarkMenuBar: true)!)
                assert(ink == 0, "owl \(scene.name) frame \(index): \(ink) px of ink on the canvas edge")
            }
        }
    }

    /// Pixels in the outermost one-pixel ring with any alpha.
    private static func edgeInk(_ image: CGImage) -> Int {
        let (w, h) = (image.width, image.height)
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let context = CGContext(data: &rgba, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var ink = 0
        for y in 0..<h { for x in 0..<w where (x == 0 || y == 0 || x == w - 1 || y == h - 1) && rgba[(y * w + x) * 4 + 3] > 0 {
            ink += 1
        } }
        return ink
    }
    #endif
}
