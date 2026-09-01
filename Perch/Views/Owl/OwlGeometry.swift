import SwiftUI

/// Ratios against a 24pt owl. Everything downstream multiplies by
/// `size / baseSize`, so the whole face scales from one number.
enum OwlGeometry {
    static let baseSize: CGFloat = 24
    static let faceWidthRatio: CGFloat = 21
    static let faceHeightRatio: CGFloat = 20

    /// No ear tufts. Horns on a round head read as a cat, which is exactly what
    /// the first pass looked like. What says owl without them is the facial
    /// disc: a heart, broad and notched across the brow, tapering to a rounded
    /// chin. No other animal has that silhouette.
    ///
    /// Circles, not the robot's 3.4x4.4 bars — nearly double the area, which is
    /// the reason to be an owl at all: eye state stays readable at menu bar size.
    static let eyeSpacingRatio: CGFloat = 4.0
    static let eyeWidthRatio: CGFloat = 7.0
    static let eyeHeightRatio: CGFloat = 7.0
    static let minEyeHeightRatio: CGFloat = 0.7
    /// The eyes ride high in the disc — an owl's sit up under the brow, and a
    /// low-set eye is part of what made the first pass read as a cat.
    static let eyeCenterOffsetRatio: CGFloat = 1.6

    static let beakWidthRatio: CGFloat = 2.4
    static let beakTopRatio: CGFloat = 2.1
    static let beakDepthRatio: CGFloat = 3.6

    static func eyeOpenness(for state: OwlHead.EyeState) -> CGFloat {
        switch state {
        case .open: 1.0
        case .halfClosed: 0.35
        case .closed: 0.0
        case .wide: 1.25
        }
    }

    /// The facial disc. Four curves: out over each brow dome from the notch,
    /// then both cheeks down into a single rounded chin. Every control point is a
    /// fraction of `rect`, so the disc scales with no scale argument.
    static func headPath(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let notch = CGPoint(x: rect.midX, y: rect.minY + 0.13 * h)   // brow dip
        let widestY = rect.minY + 0.40 * h                           // cheeks at full width
        let overshoot = rect.minY - 0.05 * h                         // brow domes clear the box
        let chin = CGPoint(x: rect.midX, y: rect.maxY)

        var path = Path()
        path.move(to: notch)
        path.addCurve(                                       // left brow dome
            to: CGPoint(x: rect.minX, y: widestY),
            control1: CGPoint(x: rect.midX - 0.22 * w, y: overshoot),
            control2: CGPoint(x: rect.minX, y: rect.minY + 0.04 * h)
        )
        path.addCurve(                                       // left cheek into the chin
            to: chin,
            control1: CGPoint(x: rect.minX, y: rect.minY + 0.76 * h),
            control2: CGPoint(x: rect.midX - 0.30 * w, y: rect.maxY)
        )
        path.addCurve(                                       // right cheek back up
            to: CGPoint(x: rect.maxX, y: widestY),
            control1: CGPoint(x: rect.midX + 0.30 * w, y: rect.maxY),
            control2: CGPoint(x: rect.maxX, y: rect.minY + 0.76 * h)
        )
        path.addCurve(                                       // right brow dome
            to: notch,
            control1: CGPoint(x: rect.maxX, y: rect.minY + 0.04 * h),
            control2: CGPoint(x: rect.midX + 0.22 * w, y: overshoot)
        )
        path.closeSubpath()
        return path
    }

    /// A narrow downward wedge between the eyes. `eyeCenterY` is the eyes' shared
    /// centre line — the beak hangs off that rather than off the head, so it stays
    /// under the eyes as they glance around.
    static func beakPath(midX: CGFloat, eyeCenterY: CGFloat, scale: CGFloat) -> Path {
        let halfWidth = beakWidthRatio * scale / 2
        let top = eyeCenterY + beakTopRatio * scale

        var path = Path()
        path.move(to: CGPoint(x: midX - halfWidth, y: top))
        path.addLine(to: CGPoint(x: midX + halfWidth, y: top))
        path.addLine(to: CGPoint(x: midX, y: top + beakDepthRatio * scale))
        path.closeSubpath()
        return path
    }

    static func faceRect(centeredAt mid: CGPoint, scale: CGFloat) -> CGRect {
        let width = faceWidthRatio * scale
        let height = faceHeightRatio * scale
        return CGRect(x: mid.x - width / 2, y: mid.y - height / 2, width: width, height: height)
    }
}
