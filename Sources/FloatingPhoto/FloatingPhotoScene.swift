import Combine
import CoreImage
import UIKit

/// A prepared image and its motion-parallax rendering configuration.
@MainActor
public final class FloatingPhotoScene: ObservableObject {
    public let image: UIImage
    public let configuration: FloatingPhotoConfiguration
    @Published public private(set) var phase: FloatingPhotoPhase = .idle
    private(set) var renderer: FloatingPhotoRenderer?
    private var preparation: Task<FloatingPhotoRenderer, Never>?

    public init(image: UIImage, configuration: FloatingPhotoConfiguration = .default) {
        self.image = image
        self.configuration = configuration
    }

    /// Estimates relative depth once, sharing the result across concurrent calls.
    public func prepare() async {
        let task: Task<FloatingPhotoRenderer, Never>
        if let preparation {
            task = preparation
        } else {
            guard phase == .idle else { return }
            guard let source = image.floatingPhotoCIImage() else {
                phase = .failed
                return
            }
            phase = .processing
            let configuration = configuration
            task = Task.detached(priority: .userInitiated) {
                let depth = PhotoDepthEstimator(context: FloatingPhotoRenderer.context).depth(for: source)
                return FloatingPhotoRenderer(source: source, depth: depth, configuration: configuration)
            }
            preparation = task
        }
        let result = await task.value
        guard phase == .processing else { return }
        renderer = result
        phase = result.surface.hasDepth && result.device != nil ? .ready : .degraded
        preparation = nil
    }

    /// Exports the scene using the preview's camera and geometry.
    public func exportVideo(to url: URL, size: CGSize, duration: TimeInterval = 4, frameRate: Int32 = 30) async throws {
        guard let renderer else { throw FloatingPhotoError.sceneNotPrepared }
        guard size.width.isFinite, size.height.isFinite, size.width >= 1, size.height >= 1,
              duration.isFinite, duration > 0, frameRate > 0 else { throw FloatingPhotoError.unsupportedVideoSize }
        try await renderer.exportVideo(to: url, size: size, duration: duration, frameRate: frameRate)
    }
}
