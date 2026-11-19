import SwiftUI
import UIKit

/// A SwiftUI view that turns one ordinary photo into a bounded motion-parallax scene.
public struct FloatingPhotoView: View {
    @StateObject private var scene: FloatingPhotoScene
    @StateObject private var motion: FloatingPhotoMotionController
    private let preferredMotion: FloatingPhotoMotion

    public init(
        image: UIImage,
        configuration: FloatingPhotoConfiguration = .default,
        motion: FloatingPhotoMotion = .device
    ) {
        let scene = FloatingPhotoScene(image: image, configuration: configuration)
        _scene = StateObject(wrappedValue: scene)
        _motion = StateObject(wrappedValue: FloatingPhotoMotionController(configuration: configuration))
        self.preferredMotion = motion
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let layers = scene.previewLayers {
                    layerView(layers: layers, size: proxy.size)
                } else {
                    Image(uiImage: scene.image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .contentShape(Rectangle())
        }
        .task {
            await scene.prepare()
            if case .device = preferredMotion {
                motion.start()
            }
        }
        .onDisappear {
            motion.stop()
        }
        .accessibilityLabel("Floating photo")
    }

    private func layerView(layers: FloatingPhotoPreviewLayers, size: CGSize) -> some View {
        ZStack {
            Image(uiImage: layers.background)
                .resizable()
                .scaledToFill()
                .scaleEffect(scene.configuration.backgroundScale)
                .offset(
                    x: currentOffset.width * scene.configuration.backgroundDepth * size.width,
                    y: currentOffset.height * scene.configuration.backgroundDepth * size.height
                )

            Image(uiImage: layers.backgroundBlurred)
                .resizable()
                .scaledToFill()
                .scaleEffect(scene.configuration.backgroundScale)
                .opacity(scene.configuration.backgroundBlurOpacity)
                .offset(
                    x: currentOffset.width * scene.configuration.backgroundDepth * size.width,
                    y: currentOffset.height * scene.configuration.backgroundDepth * size.height
                )

            if let foreground = layers.foreground {
                Image(uiImage: foreground)
                    .resizable()
                    .scaledToFill()
                    .offset(
                        x: currentOffset.width * scene.configuration.foregroundDepth * size.width,
                        y: currentOffset.height * scene.configuration.foregroundDepth * size.height
                    )
                    .shadow(
                        color: .black.opacity(0.22),
                        radius: 14,
                        x: 0,
                        y: 8
                    )
            }
        }
    }

    private var currentOffset: CGSize {
        switch preferredMotion {
        case .device:
            return motion.offset
        case let .staticOffset(x, y):
            return CGSize(width: x, height: y)
        }
    }
}
