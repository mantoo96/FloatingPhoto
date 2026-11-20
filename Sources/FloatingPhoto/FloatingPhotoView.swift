import MetalKit
import SwiftUI

/// A SwiftUI view that turns one ordinary photo into a bounded motion-parallax scene.
public struct FloatingPhotoView: View {
    private let image: UIImage
    private let configuration: FloatingPhotoConfiguration
    private let motion: FloatingPhotoMotion

    public init(image: UIImage, configuration: FloatingPhotoConfiguration = .default, motion: FloatingPhotoMotion = .device) {
        self.image = image
        self.configuration = configuration
        self.motion = motion
    }

    private struct SceneID: Hashable {
        let photo: ObjectIdentifier
        let configuration: FloatingPhotoConfiguration
    }

    public var body: some View {
        SceneView(image: image, configuration: configuration, motion: motion)
            .id(SceneID(photo: ObjectIdentifier(image), configuration: configuration))
    }
}

private struct SceneView: View {
    @StateObject private var scene: FloatingPhotoScene
    @StateObject private var sensor: FloatingPhotoMotionController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var appPhase
    let motion: FloatingPhotoMotion

    init(image: UIImage, configuration: FloatingPhotoConfiguration, motion: FloatingPhotoMotion) {
        _scene = StateObject(wrappedValue: FloatingPhotoScene(image: image, configuration: configuration))
        _sensor = StateObject(wrappedValue: FloatingPhotoMotionController(configuration: configuration))
        self.motion = motion
    }

    private var track: Bool {
        motion == .device && !reduceMotion && appPhase == .active
    }

    private var offset: CGSize {
        if reduceMotion { return .zero }
        switch motion {
        case .device: return sensor.offset
        case let .staticOffset(x, y): return CGSize(width: x, height: y)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            if let renderer = scene.renderer, renderer.device != nil {
                SurfaceView(renderer: renderer, offset: offset, followsDeviceAxes: motion == .device)
            } else {
                Image(uiImage: scene.image).resizable().scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(max(1, scene.configuration.backgroundScale)).clipped()
            }
        }
        .task { await scene.prepare() }
        .onAppear { if track { sensor.start() } }
        .onChange(of: track) { enabled in if enabled { sensor.start() } else { sensor.stop() } }
        .onDisappear { sensor.stop() }
        .accessibilityLabel("Floating photo")
    }
}

private struct SurfaceView: UIViewRepresentable {
    let renderer: FloatingPhotoRenderer
    let offset: CGSize
    let followsDeviceAxes: Bool

    func makeUIView(context: Context) -> PhotoCanvas {
        let view = PhotoCanvas(frame: .zero, device: renderer.device)
        // Motion updates arrive independently of SwiftUI state changes. Keep
        // the Metal view drawing continuously so each frame uses the latest
        // sensor sample without waiting for a view invalidation.
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60
        view.colorPixelFormat = .bgra8Unorm
        // The renderer uses a Metal render encoder and can keep the drawable
        // framebuffer-only for the normal MTKView presentation path.
        view.framebufferOnly = true
        view.isOpaque = true
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        return view
    }

    func updateUIView(_ view: PhotoCanvas, context: Context) {
        view.renderer = renderer
        view.offset = offset
        view.followsDeviceAxes = followsDeviceAxes
    }
}

private final class PhotoCanvas: MTKView {
    var renderer: FloatingPhotoRenderer?
    var offset = CGSize.zero
    var followsDeviceAxes = false

    override func draw(_ rect: CGRect) {
        guard let renderer, let drawable = currentDrawable else { return }
        var position = offset
        if followsDeviceAxes {
            switch window?.windowScene?.interfaceOrientation {
            case .landscapeLeft: position = CGSize(width: -offset.height, height: offset.width)
            case .landscapeRight: position = CGSize(width: offset.height, height: -offset.width)
            case .portraitUpsideDown: position = CGSize(width: -offset.width, height: -offset.height)
            default: break
            }
        }
        guard let commands = renderer.frame(at: position, into: drawable.texture) else { return }
        commands.present(drawable)
        commands.commit()
    }
}
