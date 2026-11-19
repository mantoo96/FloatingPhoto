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
                if let layers = scene.layers {
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

    @ViewBuilder
    private func layerView(layers: FloatingPhotoLayers, size: CGSize) -> some View {
        let offset: CGSize
        switch preferredMotion {
        case .device:
            offset = motion.offset
        case let .staticOffset(x, y):
            offset = CGSize(width: x, height: y)
        }

        ZStack {
            Image(uiImage: layers.background.floatingPhotoUIImage() ?? scene.image)
                .resizable()
                .scaledToFill()
                .scaleEffect(scene.configuration.backgroundScale)
                .offset(
                    x: offset.width * scene.configuration.backgroundDepth * size.width,
                    y: offset.height * scene.configuration.backgroundDepth * size.height
                )

            if let foreground = layers.foreground?.floatingPhotoUIImage() {
                Image(uiImage: foreground)
                    .resizable()
                    .scaledToFill()
                    .offset(
                        x: offset.width * scene.configuration.foregroundDepth * size.width,
                        y: offset.height * scene.configuration.foregroundDepth * size.height
                    )
            }
        }
    }
}
