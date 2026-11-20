import AVFoundation
import CoreImage
import MetalKit

/// Preview and movie frames project one photo through a continuous depth field.
final class FloatingPhotoRenderer {
    static let context = CIContext(options: [.cacheIntermediates: false])
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    let surface: PhotoSurface
    let configuration: FloatingPhotoConfiguration
    private let source: CIImage
    private let drawing: Drawing?

    var device: MTLDevice? { drawing?.gpu.device }

    init(
        source: CIImage,
        depth: CIImage?,
        foregroundMask: CIImage? = nil,
        configuration: FloatingPhotoConfiguration
    ) {
        self.source = source
        self.configuration = configuration
        let surface = PhotoSurface(
            imageSize: source.extent.size,
            depth: depth,
            foregroundMask: foregroundMask,
            configuration: configuration,
            context: Self.context
        )
        self.surface = surface
        self.drawing = Drawing(source: source, surface: surface)
    }

    private struct GPU {
        let device: MTLDevice
        let queue: MTLCommandQueue
        let pipeline: MTLRenderPipelineState

        static let shared = GPU()

        init?() {
            guard
                let device = MTLCreateSystemDefaultDevice(),
                let queue = device.makeCommandQueue(),
                let url = Bundle.module.url(forResource: "PhotoSurface", withExtension: "metal"),
                let source = try? String(contentsOf: url, encoding: .utf8),
                let library = try? device.makeLibrary(source: source, options: nil)
            else { return nil }

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.label = "FloatingPhoto continuous parallax"
            descriptor.vertexFunction = library.makeFunction(name: "projectPhoto")
            descriptor.fragmentFunction = library.makeFunction(name: "samplePhoto")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }

            self.device = device
            self.queue = queue
            self.pipeline = pipeline
        }
    }

    private struct PhotoUniforms {
        var camera: SIMD4<Float>
        var effects: SIMD4<Float>
        var blur: SIMD4<Float>
    }

    private struct Drawing {
        let gpu: GPU
        let photo: MTLTexture
        let depth: MTLTexture
        let depthAvailable: Bool

        init?(source: CIImage, surface: PhotoSurface) {
            guard let gpu = GPU.shared else { return nil }

            let sourceBounds = source.extent
            let scale = min(1, 4096 / max(sourceBounds.width, sourceBounds.height))
            let width = max(1, Int((sourceBounds.width * scale).rounded()))
            let height = max(1, Int((sourceBounds.height * scale).rounded()))
            let bounds = CGRect(x: 0, y: 0, width: width, height: height)
            let transform = CGAffineTransform(
                a: CGFloat(width) / sourceBounds.width,
                b: 0,
                c: 0,
                d: CGFloat(height) / sourceBounds.height,
                tx: -sourceBounds.minX * CGFloat(width) / sourceBounds.width,
                ty: -sourceBounds.minY * CGFloat(height) / sourceBounds.height
            )
            let rasterized = source.transformed(by: transform)

            guard
                let image = FloatingPhotoRenderer.context.createCGImage(
                    rasterized,
                    from: bounds,
                    format: .RGBA8,
                    colorSpace: FloatingPhotoRenderer.sRGB
                ),
                let photo = try? MTKTextureLoader(device: gpu.device).newTexture(
                    cgImage: image,
                    options: [
                        .origin: MTKTextureLoader.Origin.topLeft,
                        .SRGB: false,
                        .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue)
                    ]
                )
            else { return nil }

            let depthValues = surface.depthValues
            let depthWidth = depthValues == nil ? 1 : surface.columns + 1
            let depthHeight = depthValues == nil ? 1 : surface.rows + 1
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .r8Unorm,
                width: depthWidth,
                height: depthHeight,
                mipmapped: false
            )
            descriptor.usage = .shaderRead
            guard let depth = gpu.device.makeTexture(descriptor: descriptor) else { return nil }

            if let depthValues {
                let bytes = depthValues.map { UInt8(min(1, max(0, $0)) * 255) }
                bytes.withUnsafeBytes { rawBuffer in
                    depth.replace(
                        region: MTLRegionMake2D(0, 0, depthWidth, depthHeight),
                        mipmapLevel: 0,
                        withBytes: rawBuffer.baseAddress!,
                        bytesPerRow: depthWidth
                    )
                }
            } else {
                var value: UInt8 = 128
                depth.replace(
                    region: MTLRegionMake2D(0, 0, 1, 1),
                    mipmapLevel: 0,
                    withBytes: &value,
                    bytesPerRow: 1
                )
            }

            self.gpu = gpu
            self.photo = photo
            self.depth = depth
            self.depthAvailable = depthValues != nil
        }
    }

    /// The caller presents or waits on this command buffer after encoding.
    func frame(at offset: CGSize, into target: MTLTexture) -> MTLCommandBuffer? {
        guard let drawing, let commands = drawing.gpu.queue.makeCommandBuffer() else { return nil }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return nil }

        let canvas = CGSize(width: target.width, height: target.height)
        let camera = surface.camera(at: offset, canvas: canvas, configuration: configuration)
        let depthScale = max(0.35, min(1.5, configuration.foregroundDepth + configuration.backgroundDepth))
        let effects = SIMD4<Float>(
            1 / Float(max(1, drawing.photo.width)),
            1 / Float(max(1, drawing.photo.height)),
            0.9 * Float(depthScale),
            0.5
        )
        let blur = SIMD4<Float>(
            Float(min(12, max(0, configuration.backgroundBlur))),
            Float(min(1, max(0, configuration.backgroundBlurOpacity))),
            drawing.depthAvailable ? 1 : 0,
            0
        )
        var uniforms = PhotoUniforms(camera: camera, effects: effects, blur: blur)

        encoder.setRenderPipelineState(drawing.gpu.pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<PhotoUniforms>.stride, index: 0)
        encoder.setFragmentTexture(drawing.photo, index: 0)
        encoder.setFragmentTexture(drawing.depth, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        return commands
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

        var cache: CVMetalTextureCache?
        if let device, CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) != kCVReturnSuccess {
            throw FloatingPhotoError.exportFailed
        }
        guard let pool = adaptor.pixelBufferPool else { throw FloatingPhotoError.exportFailed }

        let frameCount = Int(ceil(duration * Double(frameRate)))
        for index in 0..<frameCount {
            try Task.checkCancellation()
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing else { throw writer.error ?? FloatingPhotoError.exportFailed }
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            let angle = 2 * Double.pi * Double(index) / Double(max(1, frameCount - 1))
            let offset = CGSize(width: sin(angle), height: 0.3 * sin(2 * angle))
            var buffer: CVPixelBuffer?
            guard
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
                let buffer
            else { throw FloatingPhotoError.exportFailed }
            try render(at: offset, into: buffer, cache: cache)
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: frameRate)) else {
                throw writer.error ?? FloatingPhotoError.exportFailed
            }
        }

        input.markAsFinished()
        await withCheckedContinuation { continuation in writer.finishWriting { continuation.resume() } }
        guard writer.status == .completed else { throw writer.error ?? FloatingPhotoError.exportFailed }
    }

    private func render(at offset: CGSize, into buffer: CVPixelBuffer, cache: CVMetalTextureCache?) throws {
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        if let cache {
            var backing: CVMetalTexture?
            guard
                CVMetalTextureCacheCreateTextureFromImage(
                    nil,
                    cache,
                    buffer,
                    nil,
                    .bgra8Unorm,
                    width,
                    height,
                    0,
                    &backing
                ) == kCVReturnSuccess,
                let backing,
                let target = CVMetalTextureGetTexture(backing),
                let commands = frame(at: offset, into: target)
            else { throw FloatingPhotoError.exportFailed }
            commands.commit()
            withExtendedLifetime(backing) { commands.waitUntilCompleted() }
            if commands.status != .completed { throw commands.error ?? FloatingPhotoError.exportFailed }
        } else {
            let bounds = CGRect(x: 0, y: 0, width: width, height: height)
            let fit = max(bounds.width / source.extent.width, bounds.height / source.extent.height) * max(1, configuration.backgroundScale)
            let transform = CGAffineTransform(
                a: fit,
                b: 0,
                c: 0,
                d: fit,
                tx: bounds.midX - source.extent.midX * fit,
                ty: bounds.midY - source.extent.midY * fit
            )
            Self.context.render(source.transformed(by: transform), to: buffer, bounds: bounds, colorSpace: Self.sRGB)
        }
    }
}
