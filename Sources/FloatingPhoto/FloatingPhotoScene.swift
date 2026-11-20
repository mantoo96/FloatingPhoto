import Combine
import CoreImage
import UIKit

/// Owns the source photo and the depth data shared by previews and video exports.
///
/// Keep one instance per photo and configuration. Pass it to ``FloatingPhotoView/init(scene:motion:)``
/// for automatic preparation, or call ``prepare()`` explicitly before a headless export.
@MainActor
public final class FloatingPhotoScene: ObservableObject {
    /// The original image supplied by the caller, also used for the loading and fallback views.
    public let image: UIImage
    /// The settings used for both live rendering and exported frames.
    public let configuration: FloatingPhotoConfiguration
    /// Preparation state published on the main actor. Observe `$phase` or use `@ObservedObject` in SwiftUI.
    @Published public private(set) var phase: FloatingPhotoPhase = .idle

    /// Indicates whether ``exportVideo(to:size:duration:frameRate:)`` can use this scene.
    /// Both a depth scene and a prepared static fallback can be exported.
    public var canExport: Bool { renderer != nil }

    private(set) var renderer: FloatingPhotoRenderer?
    private var preparation: Task<FloatingPhotoRenderer, Never>?

    /// Creates an idle scene. Preparation begins when a preview appears or when you call ``prepare()``.
    ///
    /// - Parameters:
    ///   - image: The source photo in its original orientation.
    ///   - configuration: The crop, depth and motion settings for this photo.
    public init(image: UIImage, configuration: FloatingPhotoConfiguration = .default) {
        self.image = image
        self.configuration = configuration
    }

    /// Prepares the scene once. Concurrent callers await the same work and later calls reuse its result.
    ///
    /// After this method returns, inspect ``phase`` for `.ready`, `.degraded` (static fallback),
    /// or `.failed` (unusable image). Preparation can finish before a preview appears onscreen.
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
                let estimate = PhotoDepthEstimator(context: FloatingPhotoRenderer.context).estimate(for: source)
                return FloatingPhotoRenderer(
                    source: source,
                    depth: estimate.depth,
                    foregroundMask: estimate.foregroundMask,
                    configuration: configuration
                )
            }
            preparation = task
        }
        let result = await task.value
        guard phase == .processing else { return }
        renderer = result
        phase = result.surface.depthValues != nil && result.device != nil ? .ready : .degraded
        preparation = nil
    }

    /// Writes an H.264 MP4 using the prepared scene and a repeatable tilt path.
    ///
    /// - Parameters:
    ///   - url: A local movie destination. An existing file at this path is replaced.
    ///   - size: Output dimensions in pixels. Use even dimensions supported by the H.264 encoder.
    ///   - duration: Clip length in seconds. The default is four seconds.
    ///   - frameRate: Number of frames per second. The default is 30.
    /// - Throws: ``FloatingPhotoError/sceneNotPrepared`` if the scene has no renderer,
    ///   or an error if the settings are invalid, encoding fails, or the task is cancelled.
    public func exportVideo(to url: URL, size: CGSize, duration: TimeInterval = 4, frameRate: Int32 = 30) async throws {
        guard let renderer else { throw FloatingPhotoError.sceneNotPrepared }
        guard size.width.isFinite, size.height.isFinite, size.width >= 1, size.height >= 1,
              duration.isFinite, duration > 0, frameRate > 0 else { throw FloatingPhotoError.unsupportedVideoSize }
        try await renderer.exportVideo(to: url, size: size, duration: duration, frameRate: frameRate)
    }
}
