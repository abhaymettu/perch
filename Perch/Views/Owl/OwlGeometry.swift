import SwiftUI

/// Ratios against a 24pt owl. Everything downstream multiplies by
/// `size / baseSize`, so the whole face scales from one number.
enum OwlGeometry {
    static let baseSize: CGFloat = 24
    /// 1.5:1. A head taller than wide reads as a cat or a bear; an owl at rest
    /// is squat, and the width is also what keeps two eyes legible at 22pt.
    static let faceWidthRatio: CGFloat = 23
    static let faceHeightRatio: CGFloat = 15.4

    /// Circles, not the robot's 3.4x4.4 bars — nearly double the area, which is
    /// the reason to be an owl at all: eye state stays readable at menu bar size.
    static let eyeSpacingRatio: CGFloat = 3.7
    static let eyeWidthRatio: CGFloat = 5.8
    static let eyeHeightRatio: CGFloat = 5.8
    static let minEyeHeightRatio: CGFloat = 0.7
    /// The eyes ride high in the head — an owl's sit up under the brow, and a
    /// low-set eye is part of what made the first pass read as a cat.
    static let eyeCenterOffsetRatio: CGFloat = 0.8

    static let beakWidthRatio: CGFloat = 3.8
    static let beakTopRatio: CGFloat = 0.6
    static let beakDepthRatio: CGFloat = 5.4

    static func eyeOpenness(for state: OwlHead.EyeState) -> CGFloat {
        switch state {
        case .open: 1.0
        case .halfClosed: 0.35
        case .closed: 0.0
        case .wide: 1.25
        }
    }

    /// The head. A wide squircle, not an animal outline: every attempt at a
    /// drawn silhouette (tufts, brow points, a tapered chin) read as a cat or a
    /// mask at 22pt. The owl comes from the features, not the shape — glaring
    /// sliced eyes and a beak inside a squat frame, which is also the only thing
    /// that survives being a monochrome template image.
    ///
    /// `.continuous` matters: a circular corner radius makes it a lozenge.
    static func headPath(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: rect.height * 0.42, style: .continuous)
    }

    /// How far the facial disc sits inside the head edge. An owl's face is a
    /// dish, and one inner ring is what turns a plain squircle into a face.
    static let faceDiscInsetRatio: CGFloat = 1.7

    /// A circle with the top-inner corner sliced off by the brow. Plain circles
    /// read owlish but placid; the cut is what makes it glare. The slice is
    /// subtracted from the eye rather than drawn over it so that all three
    /// renderers — panel, menu bar, app icon — get the same shape from one path.
    static func eyePath(in rect: CGRect, innerIsRight: Bool) -> Path {
        let outerY = rect.minY + 0.02 * rect.height   // barely clipped at the temple
        let innerY = rect.minY + 0.52 * rect.height   // deep cut beside the beak
        let (leftY, rightY) = innerIsRight ? (outerY, innerY) : (innerY, outerY)

        let top = rect.minY - rect.height

        var cut = Path()
        cut.move(to: CGPoint(x: rect.minX, y: leftY))
        cut.addLine(to: CGPoint(x: rect.maxX, y: rightY))
        cut.addLine(to: CGPoint(x: rect.maxX, y: top))
        cut.addLine(to: CGPoint(x: rect.minX, y: top))
        cut.closeSubpath()

        return Path(roundedRect: rect, cornerRadius: rect.width / 2).subtracting(cut)
    }

    /// A small diamond between the eyes. `eyeCenterY` is the eyes' shared centre
    /// line — the beak hangs off that rather than off the head, so it stays under
    /// the eyes as they glance around.
    static func beakPath(midX: CGFloat, eyeCenterY: CGFloat, scale: CGFloat) -> Path {
        let halfWidth = beakWidthRatio * scale / 2
        let top = eyeCenterY + beakTopRatio * scale
        let depth = beakDepthRatio * scale

        var path = Path()
        path.move(to: CGPoint(x: midX, y: top))
        path.addLine(to: CGPoint(x: midX + halfWidth, y: top + depth / 2))
        path.addLine(to: CGPoint(x: midX, y: top + depth))
        path.addLine(to: CGPoint(x: midX - halfWidth, y: top + depth / 2))
        path.closeSubpath()
        return path
    }

    static func faceRect(centeredAt mid: CGPoint, scale: CGFloat) -> CGRect {
        let width = faceWidthRatio * scale
        let height = faceHeightRatio * scale
        return CGRect(x: mid.x - width / 2, y: mid.y - height / 2, width: width, height: height)
    }
}
