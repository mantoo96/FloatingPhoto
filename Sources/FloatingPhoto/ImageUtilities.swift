import CoreImage
import ImageIO
import UIKit

extension UIImage.Orientation {
    var cgImagePropertyOrientation: CGImagePropertyOrientation {
        switch self {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

extension UIImage {
    func floatingPhotoCIImage() -> CIImage? {
        guard let pixels = ciImage ?? cgImage.map({ CIImage(cgImage: $0) }) else { return nil }
        let upright = pixels.oriented(imageOrientation.cgImagePropertyOrientation)
        let bounds = upright.extent
        guard !bounds.isEmpty, !bounds.isInfinite, bounds.width.isFinite, bounds.height.isFinite else { return nil }
        return upright.transformed(by: CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
    }
}
