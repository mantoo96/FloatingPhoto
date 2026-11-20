import AVFoundation
import CoreImage
import MetalKit

/// Preview and movie frames project the same mesh and sample the same single photo texture.
final class FloatingPhotoRenderer {
    static let context = CIContext(options: [.cacheIntermediates: false])
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    let surface: PhotoSurface
    let configuration: FloatingPhotoConfiguration
    private let source: CIImage
    private let drawing: Drawing?
    var device: MTLDevice? { drawing?.gpu.device }

    init(source: CIImage, depth: CIImage?, configuration: FloatingPhotoConfiguration) {
        self.source = source
        self.configuration = configuration
        let surface = PhotoSurface(imageSize: source.extent.size, depth: depth, configuration: configuration, context: Self.context)
        self.surface = surface
        self.drawing = Drawing(source: source, surface: surface)
    }

    private struct GPU {
        let device: MTLDevice
        let queue: MTLCommandQueue
        let pipeline: MTLRenderPipelineState

        static let shared = GPU()

        init?() {
            guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
                  let url = Bundle.module.url(forResource: "PhotoSurface", withExtension: "metal"),
                  let source = try? String(contentsOf: url, encoding: .utf8),
                  let library = try? device.makeLibrary(source: source, options: nil) else { return nil }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "projectPhoto")
            descriptor.fragmentFunction = library.makeFunction(name: "samplePhoto")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
            self.device = device
            self.queue = queue
            self.pipeline = pipeline
        }
    }

    private struct Drawing {
        let gpu: GPU
        let photo: MTLTexture
        let vertices: MTLBuffer
        let indices: MTLBuffer

        init?(source: CIImage, surface: PhotoSurface) {
            guard let gpu = GPU.shared else { return nil }
            let scale = min(1, 4096 / max(source.extent.width, source.extent.height))
            let scaled = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            // Use the exact photo bounds even when downsampling would produce a fractional last pixel.
            let bounds = CGRect(x: 0, y: 0, width: max(1, scaled.extent.width.rounded()), height: max(1, scaled.extent.height.rounded()))
            let pixels = source.transformed(by: CGAffineTransform(scaleX: bounds.width / source.extent.width,
                                                                  y: bounds.height / source.extent.height))
            guard let image = context.createCGImage(pixels, from: bounds, format: .RGBA8, colorSpace: sRGB),
                  let photo = try? MTKTextureLoader(device: gpu.device).newTexture(cgImage: image, options: [
                    .origin: MTKTextureLoader.Origin.topLeft, .SRGB: false
                  ]),
                  let vertices = gpu.device.makeBuffer(bytes: surface.vertices, length: surface.vertices.count * MemoryLayout<SIMD4<Float>>.stride),
                  let indices = gpu.device.makeBuffer(bytes: surface.indices, length: surface.indices.count * MemoryLayout<UInt16>.stride) else { return nil }
            self.gpu = gpu
            self.photo = photo
            self.vertices = vertices
            self.indices = indices
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
        var camera = surface.camera(at: offset, canvas: CGSize(width: target.width, height: target.height), configuration: configuration)
        encoder.setRenderPipelineState(drawing.gpu.pipeline)
        encoder.setVertexBuffer(drawing.vertices, offset: 0, index: 0)
        encoder.setVertexBytes(&camera, length: MemoryLayout.size(ofValue: camera), index: 1)
        encoder.setFragmentTexture(drawing.photo, index: 0)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: surface.indices.count, indexType: .uint16, indexBuffer: drawing.indices, indexBufferOffset: 0)
        encoder.endEncoding()
        return commands
    }

    func exportVideo(to url: URL, size: CGSize, duration: TimeInterval, frameRate: Int32) async throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let width = Int(size.width), height = Int(size.height)
        let settings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true, kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        guard writer.canAdd(input) else { throw FloatingPhotoError.exportFailed }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? FloatingPhotoError.exportFailed }
        defer { if writer.status == .writing { writer.cancelWriting() } }
        writer.startSession(atSourceTime: .zero)
        var cache: CVMetalTextureCache?
        if let device, CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) != kCVReturnSuccess { throw FloatingPhotoError.exportFailed }
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
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { throw FloatingPhotoError.exportFailed }
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
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        if let cache {
            var backing: CVMetalTexture?
            guard CVMetalTextureCacheCreateTextureFromImage(nil, cache, buffer, nil, .bgra8Unorm, width, height, 0, &backing) == kCVReturnSuccess,
                  let backing, let target = CVMetalTextureGetTexture(backing), let commands = frame(at: offset, into: target) else { throw FloatingPhotoError.exportFailed }
            commands.commit()
            withExtendedLifetime(backing) { commands.waitUntilCompleted() }
            if commands.status != .completed { throw commands.error ?? FloatingPhotoError.exportFailed }
        } else {
            let bounds = CGRect(x: 0, y: 0, width: width, height: height)
            let fit = max(bounds.width / source.extent.width, bounds.height / source.extent.height) * max(1, configuration.backgroundScale)
            let transform = CGAffineTransform(a: fit, b: 0, c: 0, d: fit, tx: bounds.midX - source.extent.midX * fit, ty: bounds.midY - source.extent.midY * fit)
            Self.context.render(source.transformed(by: transform), to: buffer, bounds: bounds, colorSpace: Self.sRGB)
        }
    }
}
