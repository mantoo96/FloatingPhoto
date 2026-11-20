# FloatingPhoto

Turn an ordinary photo into a SwiftUI card with a separated foreground, a softened background, and motion parallax driven by device tilt. Photos are processed on the device.

## Quick start

Add the `FloatingPhoto` product with Swift Package Manager. The library targets iOS 15 and Swift 5.7 or later.

```swift
import FloatingPhoto
import SwiftUI

struct PhotoCard: View {
    let photo: UIImage

    var body: some View {
        FloatingPhotoView(image: photo)
            .aspectRatio(3 / 4, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}
```

The first handheld position is the center of the effect. `configuration: .subtle` reduces travel. `motionSensitivity` adjusts how quickly a small tilt reaches the configured travel limit. `edgeFogOpacity` controls the soft white haze around a detected subject. `motion: .staticOffset(x: 1, y: 0)` previews a fixed camera position. Both inputs use the same travel limits. The interactive view honors Reduce Motion.

## How it works

On iOS 17 and later, Vision's foreground instance mask helps identify a usable subject fallback, while Depth Anything supplies a continuous relative-depth field. On iOS 15 and 16, Vision person segmentation remains available when no model depth is present. The renderer samples the original photo through one continuous depth surface, so nearby and distant regions move by different amounts without compositing a separate foreground sticker.

The Metal renderer uses a full-screen relief pass with bounded depth travel and a centered crop. It samples the same photo texture at every pixel, so the subject and background stay fused while their apparent positions change by depth. If depth extraction is unavailable, the library uses the foreground mask as a coarse depth field and degrades to a simpler parallax result.

The bundled Depth Anything V2 Small Core ML model supplies the relative-depth field when the device supports it. The iOS 15 and 16 path keeps Vision person segmentation as a coarse depth fallback. The model is distributed under Apache License 2.0. [Apple Core ML model catalog](https://developer.apple.com/machine-learning/models/) · [Depth Anything V2 authors](https://github.com/DepthAnything/Depth-Anything-V2) · [Bundled model license](Sources/FloatingPhoto/Resources/DepthAnything-LICENSE.txt)

## Video export

```swift
let scene = FloatingPhotoScene(image: photo)
await scene.prepare()
try await scene.exportVideo(
    to: outputURL,
    size: CGSize(width: 1080, height: 1440),
    duration: 4
)
```

The MP4 uses the same continuous depth renderer as the interactive view, starting and ending at the original motion path. The [picker demo](Demo/FloatingPhotoDemo/README.md) runs on iOS 16 or later.
