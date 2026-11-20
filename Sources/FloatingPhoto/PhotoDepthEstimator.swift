import CoreImage
import CoreML
import Vision

struct PhotoDepthEstimate {
    let depth: CIImage?
    let foregroundMask: CIImage?
}

struct PhotoDepthEstimator {
    let context: CIContext

    func estimate(for image: CIImage) -> PhotoDepthEstimate {
#if compiler(>=5.9)
        if #available(iOS 17.0, *) {
            let mask = try? foregroundInstanceMask(for: image)
            let depth = Self.model.flatMap { try? inferredDepth(for: image, model: $0) } ?? mask
            return PhotoDepthEstimate(depth: depth, foregroundMask: mask)
        }
#endif
        let mask = try? personMask(for: image)
        return PhotoDepthEstimate(depth: mask, foregroundMask: mask)
    }

    func depth(for image: CIImage) -> CIImage? {
        estimate(for: image).depth
    }

#if compiler(>=5.9)
    private static let predictions = DispatchQueue(label: "FloatingPhoto.depth-predictions")

    @available(iOS 17.0, *)
    private static let model: MLModel? = {
        guard let url = Bundle.module.url(forResource: "DepthAnythingV2SmallF16P6", withExtension: "mlmodelc") else { return nil }
        return try? MLModel(contentsOf: url)
    }()

    @available(iOS 17.0, *)
    private func inferredDepth(for image: CIImage, model: MLModel) throws -> CIImage? {
        guard let input = model.modelDescription.inputDescriptionsByName["image"]?.imageConstraint else { return nil }
        let width = input.pixelsWide, height = input.pixelsHigh
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let scale = min(bounds.width / image.extent.width, bounds.height / image.extent.height)
        let fit = CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                    tx: bounds.midX - image.extent.midX * scale,
                                    ty: bounds.midY - image.extent.midY * scale)
        var buffer: CVPixelBuffer?
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                                  [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer) == kCVReturnSuccess,
              let buffer else { return nil }
        let padded = image.transformed(by: fit).clampedToExtent()
        context.render(padded, to: buffer, bounds: bounds, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        let features = try MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: buffer)])
        let prediction = try Self.predictions.sync { try model.prediction(from: features) }
        guard let output = prediction.featureValue(for: "depth")?.imageBufferValue else { return nil }
        // Inverse depth is numeric data. Applying a display transfer function to it changes the geometry.
        let depth = CIImage(cvPixelBuffer: output, options: [.colorSpace: NSNull()])
        return depth.transformed(by: fit.inverted()).cropped(to: image.extent)
    }
#endif

    private func personMask(for image: CIImage) throws -> CIImage? {
        let handler = VNImageRequestHandler(ciImage: image)
#if swift(>=5.9)
        guard let people = try personMaskRequest(handler) else { return nil }
#else
        guard let people = try personMaskRequest(handler) else { return nil }
#endif
        let mask = CIImage(cvPixelBuffer: people, options: [.colorSpace: NSNull()])
        return Self.normalize(mask, to: image.extent)
    }

    private func personMaskRequest(_ handler: VNImageRequestHandler) throws -> CVPixelBuffer? {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        try handler.perform([request])
        return request.results?.first?.pixelBuffer
    }

#if compiler(>=5.9)
    @available(iOS 17.0, *)
    private func foregroundInstanceMask(for image: CIImage) throws -> CIImage? {
        let handler = VNImageRequestHandler(ciImage: image)
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let result = request.results?.first, !result.allInstances.isEmpty else { return nil }
        let buffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
        return Self.normalize(CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()]), to: image.extent)
    }
#endif

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
