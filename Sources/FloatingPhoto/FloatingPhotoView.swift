import MetalKit
import SwiftUI

/// Displays a photo while preparing its depth effect, then follows the chosen camera input.
///
/// Use ``init(image:configuration:motion:)`` for a standalone card. Use
/// ``init(scene:motion:)`` to share preparation with another view or a video export.
public struct FloatingPhotoView: View {
    private enum Source {
        case image(UIImage, FloatingPhotoConfiguration)
        case scene(FloatingPhotoScene)
    }

    private let source: Source
    private let motion: FloatingPhotoMotion

    /// Creates a preview that owns and automatically prepares a scene for the supplied photo.
    ///
    /// - Parameters:
    ///   - image: The original photo. Its orientation is respected.
    ///   - configuration: Depth, crop and motion settings. A new image or configuration starts a new scene.
    ///   - motion: The camera input. The default follows device tilt while the app is active.
    public init(image: UIImage, configuration: FloatingPhotoConfiguration = .default, motion: FloatingPhotoMotion = .device) {
        self.source = .image(image, configuration)
        self.motion = motion
    }

    /// Displays a caller-owned scene and prepares it on appearance if needed.
    ///
    /// - Parameters:
    ///   - scene: The same instance you can observe or use with ``FloatingPhotoScene/exportVideo(to:size:duration:frameRate:)``.
    ///   - motion: The camera input for this view. Changing it reuses the prepared scene.
    public init(scene: FloatingPhotoScene, motion: FloatingPhotoMotion = .device) {
        self.source = .scene(scene)
        self.motion = motion
    }

    public var body: some View {
        statusOverlay { phase in
            if phase == .idle || phase == .processing {
                ProgressView()
                    .padding(12)
                    .background(.regularMaterial, in: Circle())
            }
        }
    }

    /// Replaces the preview's progress indicator with a SwiftUI overlay for the visible phase.
    ///
    /// The view reports `.processing` until its first depth frame appears onscreen, even if
    /// ``FloatingPhotoScene/phase`` already permits export. A static fallback reports `.degraded`.
    ///
    /// - Parameter content: Builds the overlay for each phase. Return `EmptyView()` to leave the photo uncovered.
    @MainActor @ViewBuilder
    public func statusOverlay<Overlay: View>(@ViewBuilder _ content: @escaping (FloatingPhotoPhase) -> Overlay) -> some View {
        switch source {
        case let .image(image, configuration):
            ImageSceneView(image: image, configuration: configuration, motion: motion, overlay: content)
                .id(SceneID(photo: ObjectIdentifier(image), configuration: configuration))
        case let .scene(scene):
            SceneView(scene: scene, motion: motion, overlay: content)
                .id(ObjectIdentifier(scene))
        }
    }

    private struct SceneID: Hashable {
        let photo: ObjectIdentifier
        let configuration: FloatingPhotoConfiguration
    }
}

private struct ImageSceneView<Overlay: View>: View {
    @StateObject private var scene: FloatingPhotoScene
    let motion: FloatingPhotoMotion
    let overlay: (FloatingPhotoPhase) -> Overlay

    init(image: UIImage, configuration: FloatingPhotoConfiguration, motion: FloatingPhotoMotion, overlay: @escaping (FloatingPhotoPhase) -> Overlay) {
        _scene = StateObject(wrappedValue: FloatingPhotoScene(image: image, configuration: configuration))
        self.motion = motion
        self.overlay = overlay
    }

    var body: some View {
        SceneView(scene: scene, motion: motion, overlay: overlay)
    }
}

private struct SceneView<Overlay: View>: View {
    @ObservedObject var scene: FloatingPhotoScene
    @StateObject private var sensor: FloatingPhotoMotionController
    @State private var hasPresentedFrame = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var appPhase
    let motion: FloatingPhotoMotion
    let overlay: (FloatingPhotoPhase) -> Overlay

    init(scene: FloatingPhotoScene, motion: FloatingPhotoMotion, overlay: @escaping (FloatingPhotoPhase) -> Overlay) {
        self.scene = scene
        _sensor = StateObject(wrappedValue: FloatingPhotoMotionController(configuration: scene.configuration))
        self.motion = motion
        self.overlay = overlay
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

    private var visiblePhase: FloatingPhotoPhase {
        scene.phase == .ready && !hasPresentedFrame ? .processing : scene.phase
    }

    private func revealPhoto() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
            hasPresentedFrame = true
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if scene.phase == .ready, let renderer = scene.renderer {
                    SurfaceView(renderer: renderer, offset: offset, followsDeviceAxes: motion == .device,
                                onFirstFrame: hasPresentedFrame ? nil : revealPhoto)
                }
                if !hasPresentedFrame {
                    Image(uiImage: scene.image).resizable().scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(max(1, scene.configuration.backgroundScale))
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Floating photo")
            .accessibilityAddTraits(.isImage)
            .overlay { self.overlay(visiblePhase) }
        }
        .task { await scene.prepare() }
        .onAppear { if track { sensor.start() } }
        .onChange(of: track) { enabled in if enabled { sensor.start() } else { sensor.stop() } }
        .onDisappear { sensor.stop() }
    }
}

private struct SurfaceView: UIViewRepresentable {
    let renderer: FloatingPhotoRenderer
    let offset: CGSize
    let followsDeviceAxes: Bool
    let onFirstFrame: (() -> Void)?

    func makeUIView(context: Context) -> PhotoCanvas {
        let view = PhotoCanvas(frame: .zero, device: renderer.device)
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.isOpaque = true
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        return view
    }

    func updateUIView(_ view: PhotoCanvas, context: Context) {
        view.renderer = renderer
        view.offset = offset
        view.followsDeviceAxes = followsDeviceAxes
        view.onFirstFrame = onFirstFrame
    }

    static func dismantleUIView(_ view: PhotoCanvas, coordinator: ()) {
        view.onFirstFrame = nil
        view.isPaused = true
    }
}

private final class PhotoCanvas: MTKView {
    var renderer: FloatingPhotoRenderer?
    var offset = CGSize.zero
    var followsDeviceAxes = false
    var onFirstFrame: (() -> Void)?

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
        if onFirstFrame != nil {
            // A dropped drawable has a zero presentation time. Keep the cover until a later frame lands.
            drawable.addPresentedHandler { [weak self] frame in
                guard frame.presentedTime > 0 else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self, let reveal = self.onFirstFrame else { return }
                    self.onFirstFrame = nil
                    reveal()
                }
            }
        }
        commands.present(drawable)
        commands.commit()
    }
}
