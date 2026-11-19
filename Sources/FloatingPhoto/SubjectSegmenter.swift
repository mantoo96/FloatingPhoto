import CoreImage
import CoreVideo
import Vision

struct FloatingPhotoLayers {
    let background: CIImage
    let foreground: CIImage?
    let extent: CGRect
}

struct SubjectSegmenter {
    func makeLayers(from source: CIImage, configuration: FloatingPhotoConfiguration) throws -> FloatingPhotoLayers {
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
        let mask = CIImage(cvPixelBuffer: maskBuffer)
            .cropped(to: source.extent)

        let clear = CIImage(color: .clear).cropped(to: source.extent)
        let foreground = source
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputMaskImageKey: mask,
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
}
