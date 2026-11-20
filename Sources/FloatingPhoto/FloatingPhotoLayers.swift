import CoreImage

struct FloatingPhotoLayers {
    let background: CIImage
    let backgroundBlurred: CIImage
    let foreground: CIImage?
    let edgeFog: CIImage?
    let extent: CGRect

    init(source: CIImage, foregroundMask: CIImage?, configuration: FloatingPhotoConfiguration) {
        let extent = source.extent
        self.extent = extent
        background = source

        if configuration.backgroundBlur > 0 {
            backgroundBlurred = source
                .clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: configuration.backgroundBlur])
                .cropped(to: extent)
        } else {
            backgroundBlurred = source
        }

        guard let foregroundMask else {
            foreground = nil
            edgeFog = nil
            return
        }

        let normalizedMask = Self.normalize(foregroundMask, to: extent)
        let featheredMask = normalizedMask
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.8])
            .cropped(to: extent)
        let clear = CIImage(color: .clear).cropped(to: extent)
        foreground = source
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputMaskImageKey: featheredMask,
                kCIInputBackgroundImageKey: clear
            ])
            .cropped(to: extent)

        let fogMask = featheredMask
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: max(2, configuration.backgroundBlur * 1.6)
            ])
            .cropped(to: extent)
        edgeFog = CIImage(color: .white)
            .cropped(to: extent)
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputMaskImageKey: fogMask,
                kCIInputBackgroundImageKey: clear
            ])
            .cropped(to: extent)
    }

    private static func normalize(_ mask: CIImage, to extent: CGRect) -> CIImage {
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
