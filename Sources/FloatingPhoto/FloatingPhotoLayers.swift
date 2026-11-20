import CoreImage

struct FloatingPhotoLayers {
    /// The background plate has the extracted subject replaced by a softened fill.
    let background: CIImage
    let backgroundBlurred: CIImage
    let foreground: CIImage?
    let edgeFog: CIImage?
    let extent: CGRect

    init(source: CIImage, foregroundMask: CIImage?, configuration: FloatingPhotoConfiguration) {
        let extent = source.extent
        self.extent = extent

        guard let foregroundMask else {
            background = source
            backgroundBlurred = Self.blur(source, radius: configuration.backgroundBlur, extent: extent)
            foreground = nil
            edgeFog = nil
            return
        }

        let normalizedMask = Self.normalize(foregroundMask, to: extent)
        let featheredMask = normalizedMask
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.8])
            .cropped(to: extent)

        // Keep only the background in the sharp plate. The subject-shaped hole
        // is filled with a strongly softened version of the source so the
        // moving foreground has no duplicate copy behind it.
        let holeRadius = Self.backgroundHoleRadius(for: extent)
        let backgroundHole = normalizedMask
            .clampedToExtent()
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: holeRadius])
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: max(1, configuration.backgroundBlur * 0.8)])
            .cropped(to: extent)
        let backgroundMask = backgroundHole.applyingFilter("CIColorInvert").cropped(to: extent)
        let fill = Self.blur(
            source,
            radius: Self.backgroundFillRadius(for: extent, configuration: configuration),
            extent: extent
        )
        let backgroundPlate = source
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputMaskImageKey: backgroundMask,
                kCIInputBackgroundImageKey: fill
            ])
            .cropped(to: extent)

        background = backgroundPlate
        backgroundBlurred = Self.blur(backgroundPlate, radius: configuration.backgroundBlur, extent: extent)

        let clear = CIImage(color: .clear).cropped(to: extent)
        foreground = source
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputMaskImageKey: featheredMask,
                kCIInputBackgroundImageKey: clear
            ])
            .cropped(to: extent)

        // A restrained white haze softens the contact edge without covering the
        // subject itself with a second bright silhouette.
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

    private static func backgroundHoleRadius(for extent: CGRect) -> CGFloat {
        // Expand the hidden area enough to cover the small foreground travel,
        // while keeping the expansion proportional on full-resolution photos.
        min(32, max(6, min(extent.width, extent.height) * 0.012))
    }

    private static func backgroundFillRadius(
        for extent: CGRect,
        configuration: FloatingPhotoConfiguration
    ) -> CGFloat {
        let shortSide = min(extent.width, extent.height)
        return max(24, min(96, shortSide * 0.018, configuration.backgroundBlur * 3.5))
    }

    private static func blur(_ image: CIImage, radius: CGFloat, extent: CGRect) -> CIImage {
        guard radius > 0 else { return image.cropped(to: extent) }
        return image
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
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
