# FloatingPhoto

A SwiftUI-first iOS package that turns an ordinary photo into a bounded motion-parallax scene.

FloatingPhoto uses Apple's Vision foreground instance-mask request to lift noticeable subjects, Core Motion to read device tilt, and AVFoundation to export the same effect as an MP4 video. It is deliberately a 2.5D effect with a safe motion range, not a promise of full 3D reconstruction.

## Requirements

- iOS 17+
- Swift 6+
- Swift Package Manager

## Quick start

```swift
import FloatingPhoto
import PhotosUI
import SwiftUI

struct ContentView: View {
    let photo: UIImage

    var body: some View {
        FloatingPhotoView(
            image: photo,
            configuration: .init(
                intensity: 0.75,
                backgroundBlur: 6,
                maximumTilt: 0.1
            )
        )
        .aspectRatio(3 / 4, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}
```

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

## Design decisions

- `FloatingPhotoView` is the zero-configuration entry point.
- `FloatingPhotoScene` is the reusable processing and export object.
- Segmentation failure degrades to a gentle whole-image result so a user can still complete their flow.
- The exported animation uses the same renderer concept as the interactive preview.
- The package keeps the API small and leaves PhotosPicker, navigation, persistence, and sharing to the host app.

## Current scope

The package uses a subject layer over a repaired-looking blurred background. It does not reconstruct hidden geometry or guarantee clean results for large camera movements. The motion range is intentionally bounded.
