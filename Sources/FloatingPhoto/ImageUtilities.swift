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
        return input.oriented(imageOrientation.cgImagePropertyOrientation)
    }
}

extension FloatingPhotoLayers {
    @MainActor
    func makePreviewLayers() -> FloatingPhotoPreviewLayers? {
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        guard
            let backgroundCGImage = context.createCGImage(background, from: background.extent),
            let blurredCGImage = context.createCGImage(backgroundBlurred, from: backgroundBlurred.extent)
        else {
            return nil
        }

        let foregroundImage = foreground.flatMap { image in
            context.createCGImage(image, from: image.extent).map {
                UIImage(cgImage: $0, scale: 1, orientation: .up)
            }
        }

        return FloatingPhotoPreviewLayers(
            background: UIImage(cgImage: backgroundCGImage, scale: 1, orientation: .up),
            backgroundBlurred: UIImage(cgImage: blurredCGImage, scale: 1, orientation: .up),
            foreground: foregroundImage
        )
    }
}
