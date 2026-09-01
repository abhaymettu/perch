import SwiftUI

enum RobotGeometry {
    static let baseSize: CGFloat = 24
    static let faceWidthRatio: CGFloat = 20
    static let faceHeightRatio: CGFloat = 15
    static let faceCornerRadiusRatio: CGFloat = 4.5
    /// Eyes were 2.5 wide by 5.0 tall — two vertical bars on a rounded rect,
    /// which at header size reads as a domino, not a face. Nearly round, and
    /// further apart, is what makes it read as looking at you.
    static let eyeSpacingRatio: CGFloat = 3.1
    static let eyeWidthRatio: CGFloat = 3.4
    static let eyeHeightRatio: CGFloat = 4.4
    static let minEyeHeightRatio: CGFloat = 0.6
    static let eyeCenterOffsetRatio: CGFloat = 1.5

    static func eyeOpenness(for state: RobotHead.EyeState) -> CGFloat {
        switch state {
        case .open: 1.0
        case .halfClosed: 0.35
        case .closed: 0.0
        case .wide: 1.3
        }
    }
}
