import CoreGraphics
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
        guard let input = CIImage(image: self) else { return nil }
        return input.oriented(orientation.cgImagePropertyOrientation)
    }
}

extension CIImage {
    func floatingPhotoUIImage() -> UIImage? {
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        guard let cgImage = context.createCGImage(self, from: extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }
}
