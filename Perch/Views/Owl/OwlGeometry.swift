import SwiftUI

/// Ratios against a 24pt owl. Everything downstream multiplies by
/// `size / baseSize`, so the whole face scales from one number.
enum OwlGeometry {
    static let baseSize: CGFloat = 24
    /// 1.5:1. A head taller than wide reads as a cat or a bear; an owl at rest
    /// is squat, and the width is also what keeps two eyes legible at 22pt.
    static let faceWidthRatio: CGFloat = 23
    static let faceHeightRatio: CGFloat = 15.4

    /// Circles, not the robot's 3.4x4.4 bars, nearly double the area, which is
    /// the reason to be an owl at all: eye state stays readable at menu bar size.
    static let eyeSpacingRatio: CGFloat = 3.7
    static let eyeWidthRatio: CGFloat = 5.8
    /// Where an eye sits on the cylinder the menu bar owl turns on, measured
    /// from the beak. ~24°: wide enough that the far eye vanishes well before
    /// the near one reaches the edge of the head, which is what makes a turn
    /// read as depth rather than as two circles sliding.
    static let eyeAzimuth: CGFloat = 0.42
    /// A feature is dropped once it is this close to edge-on. Below it the
    /// foreshortened width is under a rendered pixel and it flickers.
    static let cullCosine: CGFloat = 0.07
    /// The eyes ride high in the head, an owl's sit up under the brow, and a
    /// low-set eye is part of what made the first pass read as a cat.
    static let eyeCenterOffsetRatio: CGFloat = 0.8

    static let beakWidthRatio: CGFloat = 3.8
    static let beakTopRatio: CGFloat = 0.6
    static let beakDepthRatio: CGFloat = 5.4

    /// The head. A wide squircle, not an animal outline: every attempt at a
    /// drawn silhouette (tufts, brow points, a tapered chin) read as a cat or a
    /// mask at 22pt. The owl comes from the features, not the shape, glaring
    /// sliced eyes and a beak inside a squat frame, which is also the only thing
    /// that survives being a monochrome template image.
    ///
    /// `.continuous` matters: a circular corner radius makes it a lozenge.
    static func headPath(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: rect.height * 0.42, style: .continuous)
    }

    /// A circle with the top-inner corner sliced off by the brow. Plain circles
    /// read owlish but placid; the cut is what makes it glare.
    ///
    /// The brow is also the eyelid. As `lid` falls from 1 the slice comes down
    /// and bows until only a sliver of the eye's lower rim is left, so a blink
    /// closes the way a lid does rather than squeezing the eye flat. Above 1
    /// the brow lifts clear and the eye is round with surprise. `cheek` is the
    /// lower lid: at 1 it leaves only the upper rim, an eye arched in a smile.
    static func eyePath(in rect: CGRect, innerIsRight: Bool, lid: CGFloat = 1, cheek: CGFloat = 0) -> Path {
        var eye = Path(ellipseIn: rect)
        let (w, h) = (rect.width, rect.height)

        let outer: CGFloat, inner: CGFloat, sag: CGFloat
        if lid >= 1 {
            let raised = min((lid - 1) / (OwlPose.wideLid - 1), 1)
            (outer, inner, sag) = (0.02 - 0.5 * raised, 0.52 - 0.6 * raised, 0)   // clear of the eye when wide
        } else {
            let open = max(lid, 0)
            (outer, inner, sag) = (0.62 - 0.6 * open, 0.62 - 0.1 * open, 0.27 * (1 - open))
        }
        if inner > 0 {
            let (leftY, rightY) = innerIsRight ? (outer, inner) : (inner, outer)
            var brow = Path()
            brow.move(to: CGPoint(x: rect.minX, y: rect.minY + leftY * h))
            // A quadratic passes its midpoint a quarter of the way to twice
            // the control's offset, hence the doubled sag.
            brow.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + rightY * h),
                control: CGPoint(x: rect.minX + w / 2, y: rect.minY + ((leftY + rightY) / 2 + 2 * sag) * h)
            )
            brow.addLine(to: CGPoint(x: rect.maxX, y: rect.minY - h))
            brow.addLine(to: CGPoint(x: rect.minX, y: rect.minY - h))
            brow.closeSubpath()
            eye = eye.subtracting(brow)
        }

        if cheek > 0 {
            let push = min(cheek, 1)
            let ends = rect.minY + (1.3 - 0.8 * push) * h
            var lower = Path()
            lower.move(to: CGPoint(x: rect.minX, y: ends))
            lower.addQuadCurve(to: CGPoint(x: rect.maxX, y: ends),
                               control: CGPoint(x: rect.minX + w / 2, y: ends - 0.72 * push * h))
            lower.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY + h))
            lower.addLine(to: CGPoint(x: rect.minX, y: rect.maxY + h))
            lower.closeSubpath()
            eye = eye.subtracting(lower)
        }
        return eye
    }

    /// A small diamond between the eyes. `eyeCenterY` is the eyes' shared centre
    /// line, the beak hangs off that rather than off the head, so it stays under
    /// the eyes as they glance around.
    static func beakPath(midX: CGFloat, eyeCenterY: CGFloat, scale: CGFloat, depthScale: CGFloat = 1) -> Path {
        let halfWidth = beakWidthRatio * scale / 2
        let top = eyeCenterY + beakTopRatio * scale
        let depth = beakDepthRatio * scale * depthScale

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
