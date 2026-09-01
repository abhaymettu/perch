import SwiftUI

/// Ratios against a 24pt owl. Everything downstream multiplies by
/// `size / baseSize`, so the whole face scales from one number.
enum OwlGeometry {
    static let baseSize: CGFloat = 24
    static let faceWidthRatio: CGFloat = 23
    static let faceHeightRatio: CGFloat = 19

    /// Circles, not the robot's 3.4x4.4 bars — nearly double the area, which is
    /// the reason to be an owl at all: eye state stays readable at menu bar size.
    static let eyeSpacingRatio: CGFloat = 4.2
    static let eyeWidthRatio: CGFloat = 7.2
    static let eyeHeightRatio: CGFloat = 7.2
    static let minEyeHeightRatio: CGFloat = 0.7
    /// The eyes ride high in the disc — an owl's sit up under the brow, and a
    /// low-set eye is part of what made the first pass read as a cat.
    static let eyeCenterOffsetRatio: CGFloat = 0.9

    static let beakWidthRatio: CGFloat = 2.8
    static let beakTopRatio: CGFloat = 0.4
    static let beakDepthRatio: CGFloat = 4.2

    static func eyeOpenness(for state: OwlHead.EyeState) -> CGFloat {
        switch state {
        case .open: 1.0
        case .halfClosed: 0.35
        case .closed: 0.0
        case .wide: 1.25
        }
    }

    /// The head. Not a disc — a brow that dips to a V at the centre and sweeps
    /// up and out to a point above each eye, over a face that tapers to a
    /// rounded chin. Ear tufts on a round head read as a cat; this reads as a
    /// bird of prey, which is the whole difference.
    ///
    /// Every control point is a fraction of `rect`, so it needs no scale.
    static func headPath(in rect: CGRect) -> Path {
        func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + fx * rect.width, y: rect.minY + fy * rect.height)
        }

        var path = Path()
        // The tip is sharp because the two curves meeting there leave almost
        // antiparallel: control2 of the brow and control1 of the outer edge sit
        // on nearly the same line through it. Splay them and it goes blunt.
        path.move(to: p(0.50, 0.34))                                   // brow notch
        path.addCurve(to: p(0.00, 0.02),                               // up to the left tip
                      control1: p(0.33, 0.15), control2: p(0.13, 0.01))
        path.addCurve(to: p(0.16, 0.56),                               // down the outer edge
                      control1: p(0.09, 0.14), control2: p(0.13, 0.35))
        path.addCurve(to: p(0.50, 1.00),                               // left cheek into the chin
                      control1: p(0.17, 0.85), control2: p(0.31, 1.00))
        path.addCurve(to: p(0.84, 0.56),                               // right cheek back up
                      control1: p(0.69, 1.00), control2: p(0.83, 0.85))
        path.addCurve(to: p(1.00, 0.02),                               // up the outer edge
                      control1: p(0.87, 0.35), control2: p(0.91, 0.14))
        path.addCurve(to: p(0.50, 0.34),                               // back down to the notch
                      control1: p(0.87, 0.01), control2: p(0.67, 0.15))
        path.closeSubpath()
        return path
    }

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
