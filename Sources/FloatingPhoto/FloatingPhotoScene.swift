import Combine
import CoreImage
import Foundation
import UIKit

/// A prepared image and its motion-parallax rendering configuration.
@MainActor
public final class FloatingPhotoScene: ObservableObject {
    public let image: UIImage
    public let configuration: FloatingPhotoConfiguration

    @Published public private(set) var phase: FloatingPhotoPhase = .idle

    var layers: FloatingPhotoLayers?
    var previewLayers: FloatingPhotoPreviewLayers?

    private let segmenter = SubjectSegmenter()

    public init(
        image: UIImage,
        configuration: FloatingPhotoConfiguration = .default
    ) {
        self.image = image
        self.configuration = configuration
    }

    /// Performs subject lifting in the background and keeps a usable fallback if it fails.
    public func prepare() async {
        guard phase == .idle else { return }
        phase = .processing

        guard let source = image.floatingPhotoCIImage() else {
            phase = .failed
            return
        }

        let configuration = configuration
        let segmenter = segmenter
        let result: FloatingPhotoLayers? = await Task.detached(priority: .userInitiated) {
            do {
                return try segmenter.makeLayers(from: source, configuration: configuration)
            } catch {
                return nil
            }
        }.value

        let preparedLayers: FloatingPhotoLayers
        if let result {
            preparedLayers = result
            phase = .ready
        } else {
            preparedLayers = FloatingPhotoLayers(
                background: source,
                foreground: nil,
                extent: source.extent
            )
            phase = .degraded
        }

        layers = preparedLayers
        previewLayers = preparedLayers.makePreviewLayers()
    }

    /// Exports the same 2.5D scene shown by `FloatingPhotoView`.
    public func exportVideo(
        to url: URL,
        size: CGSize,
        duration: TimeInterval = 4,
        frameRate: Int32 = 30
    ) async throws {
        guard layers != nil else { throw FloatingPhotoError.sceneNotPrepared }
        guard size.width > 0, size.height > 0, duration > 0, frameRate > 0 else {
            throw FloatingPhotoError.unsupportedVideoSize
        }

        let renderer = FloatingPhotoRenderer(
            layers: layers!,
            configuration: configuration
        )
        try await renderer.exportVideo(
            to: url,
            size: size,
            duration: duration,
            frameRate: frameRate
        )
    }
}
