import CoreImage
import CoreVideo
import UIKit
import Vision

struct FloatingPhotoLayers {
    let background: CIImage
    let foreground: CIImage?
    let extent: CGRect
}

struct FloatingPhotoPreviewLayers {
    let background: UIImage
    let foreground: UIImage?
}

struct SubjectSegmenter {
    func makeLayers(from source: CIImage, configuration: FloatingPhotoConfiguration) throws -> FloatingPhotoLayers {
        let mask: CIImage

        if #available(iOS 17.0, *) {
            mask = try foregroundInstanceMask(for: source)
        } else {
            mask = try personMask(for: source)
        }

        let normalizedMask = normalize(mask, to: source.extent)
        let clear = CIImage(color: .clear).cropped(to: source.extent)
        let foreground = source
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputMaskImageKey: normalizedMask,
                kCIInputBackgroundImageKey: clear
            ])
            .cropped(to: source.extent)

        let background: CIImage
        if configuration.backgroundBlur > 0 {
            background = source
                .clampedToExtent()
                .applyingFilter(
                    "CIGaussianBlur",
                    parameters: [kCIInputRadiusKey: configuration.backgroundBlur]
                )
                .cropped(to: source.extent)
        } else {
            background = source
        }

        return FloatingPhotoLayers(
            background: background,
            foreground: foreground,
            extent: source.extent
        )
    }

    @available(iOS 17.0, *)
    private func foregroundInstanceMask(for source: CIImage) throws -> CIImage {
        let handler = VNImageRequestHandler(ciImage: source, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])

        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw FloatingPhotoError.invalidImage
        }

        let maskBuffer = try observation.generateScaledMaskForImage(
            forInstances: observation.allInstances,
            from: handler
        )
        return CIImage(cvPixelBuffer: maskBuffer)
    }

    private func personMask(for source: CIImage) throws -> CIImage {
        let handler = VNImageRequestHandler(ciImage: source, options: [:])
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        try handler.perform([request])

        guard let maskBuffer = request.results?.first?.pixelBuffer else {
            throw FloatingPhotoError.invalidImage
        }

        return CIImage(cvPixelBuffer: maskBuffer)
    }

    private func normalize(_ mask: CIImage, to extent: CGRect) -> CIImage {
        let scaleX = extent.width / mask.extent.width
        let scaleY = extent.height / mask.extent.height
        let scaled = mask.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        let translated = scaled.transformed(by: CGAffineTransform(
            translationX: extent.midX - scaled.extent.midX,
            y: extent.midY - scaled.extent.midY
        ))
        return translated.cropped(to: extent)
    }
}
