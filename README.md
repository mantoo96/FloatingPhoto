# FloatingPhoto

Display one ordinary photo as a tilt-responsive SwiftUI card. FloatingPhoto estimates relative depth on the device and uses it to move near and distant parts of the same image by different amounts.

## Add the package

Add the `FloatingPhoto` library product to your app target in Xcode using Swift Package Manager. You can select the local checkout with **Add Local…**. The library targets iOS 15 and Swift 5.7 or later. The [PhotosPicker demo](Demo/FloatingPhotoDemo/README.md) runs on iOS 16 or later.

## Show a photo

```swift
import FloatingPhoto
import SwiftUI

struct PhotoCard: View {
    let photo: UIImage

    var body: some View {
        FloatingPhotoView(image: photo)
            .aspectRatio(photo.size, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}
```

The view prepares automatically and shows a progress indicator over the original image. Once Metal presents the first depth frame, the cover fades away. Reduce Motion keeps the preview centered and reveals the frame immediately. A photo with no usable depth stays visible as a still image.

## Customize the loading and ready states

Apply `statusOverlay` directly to `FloatingPhotoView`. The closure replaces the built-in indicator and can use your app's language, materials and layout.

```swift
FloatingPhotoView(image: photo)
    .statusOverlay { phase in
        switch phase {
        case .idle, .processing:
            ProgressView("Preparing depth…")
                .padding().background(.regularMaterial, in: Capsule())
        case .ready:
            EmptyView()
        case .degraded:
            Text("Still photo")
        case .failed:
            Text("Choose another photo")
        }
    }
```

Loading bytes from a photo picker belongs to the host app. Start that indicator as soon as the user picks an item. Once you have a `UIImage`, the view's overlay covers depth preparation through first presentation. The demo uses both stages and briefly shows a tilt hint when the photo becomes interactive.

## Share preparation between preview and export

Keep one `FloatingPhotoScene` per photo and configuration. Pass that instance to the view and to your export action. Replacing it starts a new preview. A caller that needs to observe preparation can use `@ObservedObject` in SwiftUI or subscribe to `scene.$phase` on the main actor.

```swift
struct ShareableCard: View {
    @ObservedObject var scene: FloatingPhotoScene

    var body: some View {
        FloatingPhotoView(scene: scene)
            .aspectRatio(scene.image.size, contentMode: .fit)
    }
}

@MainActor
func exportMovie(for scene: FloatingPhotoScene, to file: URL) async throws {
    await scene.prepare()
    try await scene.exportVideo(
        to: file, size: CGSize(width: 1080, height: 1440),
        duration: 4, frameRate: 30
    )
}
```

Create the scene with `FloatingPhotoScene(image: photo)` when the selection changes. The preview prepares it automatically. An explicit `prepare()` during or after that work reuses the same result. Use `scene.canExport` to enable an export button. Pass a fresh local `.mp4` file URL, or a movie path you intend to replace.

| Phase | `scene.phase` | `statusOverlay` |
| --- | --- | --- |
| `.idle` | Scene created | Original photo available while preparation starts |
| `.processing` | Estimating depth and building the renderer | Original photo stays in place through first presentation |
| `.ready` | Depth scene prepared for preview or export | The first depth frame has appeared onscreen |
| `.degraded` | A static fallback can be exported | The original photo stays visible |
| `.failed` | The image could not be prepared | The host can prompt for another photo |

## Motion and depth

The opening handheld position is the center. Choose `configuration: .subtle` for less travel. `motionSensitivity` changes how much small tilts move the camera, and `intensity` controls its maximum travel. `motion: .staticOffset(x: 1, y: 0)` previews a fixed position. Export renders a repeatable camera path that starts and ends at the center.

With Swift 5.9 or later on iOS 17 or later, the bundled Depth Anything V2 Small Core ML model supplies a continuous relative-depth field. Vision foreground masks provide a coarse fallback. Earlier supported configurations use Vision person segmentation. The renderer samples the original photo with a centered crop. The legacy `edgeFogOpacity` parameter is retained for source compatibility.

The bundled Depth Anything V2 Small model is distributed under Apache License 2.0. [Apple Core ML model catalog](https://developer.apple.com/machine-learning/models/) · [Depth Anything V2 authors](https://github.com/DepthAnything/Depth-Anything-V2) · [Bundled model license](Sources/FloatingPhoto/Resources/DepthAnything-LICENSE.txt)
