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

On iOS 17 and later, Vision's foreground instance mask extracts the noticeable subject. On iOS 15 and 16, the library uses Vision person segmentation. The background becomes a cleaned photo plate with the extracted subject area softly filled. The extracted subject moves independently over that plate, so the scene produces relative depth without leaving a sharp duplicate behind. A low-opacity white haze softly blends the contact edge.

The default scene uses translations for the cleaned background plate and foreground subject. This keeps background texture stable while the subject supplies most of the depth cue. A small centered crop leaves room for the bounded movement. If extraction is unavailable, the library keeps the complete photo and degrades to a simpler motion result.

The bundled Depth Anything V2 Small Core ML model remains available for relative-depth estimation and compatibility with the package's depth surface utilities. The live card uses the subject mask for the two-layer composition so background pixels do not receive a mesh warp. The model is distributed under Apache License 2.0. [Apple Core ML model catalog](https://developer.apple.com/machine-learning/models/) · [Depth Anything V2 authors](https://github.com/DepthAnything/Depth-Anything-V2) · [Bundled model license](Sources/FloatingPhoto/Resources/DepthAnything-LICENSE.txt)

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

The MP4 uses the same two-layer renderer as the interactive view, starting and ending at the original motion path. The [picker demo](Demo/FloatingPhotoDemo/README.md) runs on iOS 16 or later.
