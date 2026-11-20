import AVFoundation
import CoreImage
import CoreVideo
import MetalKit

/// Preview and movie frames compose a sharp background, a softened background,
/// and an independently translated subject cutout.
final class FloatingPhotoRenderer {
    static let context = CIContext(options: [.cacheIntermediates: false])
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    let surface: PhotoSurface
    let configuration: FloatingPhotoConfiguration
    private let layers: FloatingPhotoLayers
    private let gpu: GPU?

    var device: MTLDevice? { gpu?.device }

    init(
        source: CIImage,
        depth: CIImage?,
        foregroundMask: CIImage? = nil,
        configuration: FloatingPhotoConfiguration
    ) {
        self.configuration = configuration
        self.surface = PhotoSurface(
            imageSize: source.extent.size,
            depth: depth,
            foregroundMask: foregroundMask,
            configuration: configuration,
            context: Self.context
        )
        self.layers = FloatingPhotoLayers(
            source: source,
            foregroundMask: foregroundMask,
            configuration: configuration
        )
        self.gpu = GPU.shared
    }

    /// The caller presents or waits on this command buffer after encoding.
    func frame(at offset: CGSize, into target: MTLTexture) -> MTLCommandBuffer? {
        guard let gpu, let commands = gpu.queue.makeCommandBuffer() else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: target.width, height: target.height)
        let image = render(at: offset, canvasSize: bounds.size)
        gpu.context.render(image, to: target, commandBuffer: commands, bounds: bounds, colorSpace: Self.sRGB)
        return commands
    }

    private func render(at offset: CGSize, canvasSize: CGSize) -> CIImage {
        let normalized = CGSize(
            width: max(-1, min(1, offset.width.isFinite ? offset.width : 0)),
            height: max(-1, min(1, offset.height.isFinite ? offset.height : 0))
        )
        let target = CGRect(origin: .zero, size: canvasSize)
        let maximumTravel = 0.035
            * min(1, max(0, configuration.intensity))
            * min(canvasSize.width, canvasSize.height)
        let backgroundTranslation = CGAffineTransform(
            translationX: normalized.width * maximumTravel * configuration.backgroundDepth,
            y: -normalized.height * maximumTravel * configuration.backgroundDepth
        )
        let foregroundTranslation = CGAffineTransform(
            translationX: normalized.width * maximumTravel * configuration.foregroundDepth,
            y: -normalized.height * maximumTravel * configuration.foregroundDepth
        )

        let background = layers.background
            .transformedToFill(target, additionalScale: configuration.backgroundScale)
            .transformed(by: backgroundTranslation)
        let softenedBackground = layers.backgroundBlurred
            .transformedToFill(target, additionalScale: configuration.backgroundScale)
            .transformed(by: backgroundTranslation)
            .withAlpha(configuration.backgroundBlurOpacity)
        var composite = softenedBackground
            .composited(over: background)
            .cropped(to: target)

        if let edgeFog = layers.edgeFog, configuration.edgeFogOpacity > 0 {
            let movedFog = edgeFog
                .transformedToFill(target, additionalScale: configuration.backgroundScale)
                .transformed(by: foregroundTranslation)
                .withAlpha(configuration.edgeFogOpacity)
            composite = movedFog.composited(over: composite).cropped(to: target)
        }

        if let foreground = layers.foreground {
            let movedForeground = foreground
                .transformedToFill(target, additionalScale: configuration.backgroundScale)
                .transformed(by: foregroundTranslation)
            composite = movedForeground.composited(over: composite).cropped(to: target)
        }
        return composite
    }

    func exportVideo(to url: URL, size: CGSize, duration: TimeInterval, frameRate: Int32) async throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let width = Int(size.width), height = Int(size.height)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        guard writer.canAdd(input) else { throw FloatingPhotoError.exportFailed }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? FloatingPhotoError.exportFailed }
        defer { if writer.status == .writing { writer.cancelWriting() } }
        writer.startSession(atSourceTime: .zero)
        guard let pool = adaptor.pixelBufferPool else { throw FloatingPhotoError.exportFailed }
        let frameCount = Int(ceil(duration * Double(frameRate)))
        let renderContext = gpu?.context ?? Self.context

        for index in 0..<frameCount {
            try Task.checkCancellation()
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing else { throw writer.error ?? FloatingPhotoError.exportFailed }
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            let progress = frameCount <= 1 ? 0 : Double(index) / Double(frameCount - 1)
            let phase = progress < 0.5 ? progress * 2 : (1 - progress) * 2
            let angle = phase * 2 - 1
            let offset = CGSize(
                width: CGFloat(angle) * configuration.intensity,
                height: CGFloat(sin(progress * .pi * 2)) * configuration.intensity
            )
            var buffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
                  let buffer else { throw FloatingPhotoError.exportFailed }
            let bounds = CGRect(x: 0, y: 0, width: width, height: height)
            renderContext.render(render(at: offset, canvasSize: size), to: buffer, bounds: bounds, colorSpace: Self.sRGB)
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: frameRate)) else {
                throw writer.error ?? FloatingPhotoError.exportFailed
            }
        }

        input.markAsFinished()
        await withCheckedContinuation { continuation in writer.finishWriting { continuation.resume() } }
        guard writer.status == .completed else { throw writer.error ?? FloatingPhotoError.exportFailed }
    }

    private struct GPU {
        let device: MTLDevice
        let queue: MTLCommandQueue
        let context: CIContext

        static let shared: GPU? = {
            guard let device = MTLCreateSystemDefaultDevice(),
                  let queue = device.makeCommandQueue() else { return nil }
            return GPU(
                device: device,
                queue: queue,
                context: CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
            )
        }()
    }
}

private extension CIImage {
    func withAlpha(_ alpha: CGFloat) -> CIImage {
        applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)
        ])
    }

    func transformedToFill(_ target: CGRect, additionalScale: CGFloat = 1) -> CIImage {
        let scale = max(target.width / extent.width, target.height / extent.height) * additionalScale
        let scaled = transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let x = target.midX - scaled.extent.midX
        let y = target.midY - scaled.extent.midY
        return scaled.transformed(by: CGAffineTransform(translationX: x, y: y))
    }
}
