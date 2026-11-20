# FloatingPhoto

Turn an ordinary photo into a SwiftUI card with motion parallax. When the phone tilts, nearby details shift against distant ones. Photos are processed on the device.

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

The first handheld position is the center of the effect. `configuration: .subtle` reduces travel. `motionSensitivity` adjusts how quickly a small tilt reaches the configured travel limit. `motion: .staticOffset(x: 1, y: 0)` previews a fixed camera position. Both inputs use the same travel limits. The interactive view honors Reduce Motion.

## How it works

`FloatingPhotoScene` estimates depth once per photo. Metal maps the original photo onto a continuous surface. At neutral the original crop is preserved. Tilting moves points according to their relative depth. The photo boundary stays fixed and the camera limits travel at steep depth changes to keep the surface continuous. A narrow strip near an occlusion can stretch under tilt because one photo only contains the visible side of the scene.

- On iOS 17 and later, builds made with Xcode 15 or later include the **19 MB Depth Anything V2 Small** Core ML model by Lihe Yang et al., converted by Apple. It estimates depth throughout the scene. If inference fails, Vision can supply a foreground mask as an approximate depth field.
- iOS 15–16 and Xcode 14 builds use Vision person segmentation. When the depth field is unavailable or flat, the scene uses gentle whole-photo motion. When Metal is unavailable, it displays the still photo.
- `foregroundDepth` and `backgroundDepth` weight near and far motion. `backgroundScale` is a centered crop of the complete photo. The existing `backgroundBlur` and `backgroundBlurOpacity` parameters now soften transitions in the depth field. Image detail stays sharp.

The model is distributed under Apache License 2.0. [Apple Core ML model catalog](https://developer.apple.com/machine-learning/models/) · [Depth Anything V2 authors](https://github.com/DepthAnything/Depth-Anything-V2) · [Bundled model license](Sources/FloatingPhoto/Resources/DepthAnything-LICENSE.txt)

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

The MP4 follows a short camera path through the same renderer as the live view, starting and ending at the original composition. The [picker demo](Demo/FloatingPhotoDemo/README.md) runs on iOS 16 or later.
