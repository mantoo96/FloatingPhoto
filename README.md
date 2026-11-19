# FloatingPhoto

A SwiftUI-first iOS package that turns an ordinary photo into a bounded motion-parallax scene.

FloatingPhoto uses Apple Vision to lift subjects, Core Motion to read device tilt, and AVFoundation to export the same effect as an MP4 video. On iOS 17 and later it uses foreground instance masks for people, pets, and other noticeable objects. On iOS 15 and 16 it uses Vision's person-segmentation request and safely falls back to a whole-image motion effect for non-person photos. It is deliberately a 2.5D effect with a safe motion range, not a promise of full 3D reconstruction.

## Requirements

- iOS 15+
- Swift 5.7+
- Xcode 14+
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
                maximumTilt: 0.1,
                backgroundBlur: 6
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

## Compatibility

- iOS 17 and later use foreground instance masks for people, pets, and other noticeable objects when built with an iOS 17 SDK.
- iOS 15 and 16 use person segmentation. Non-person images use the whole-image fallback when a subject mask is unavailable.
- Swift 5.7 and Xcode 14 can build the iOS 15 fallback path. Swift 5.9 and Xcode 15 or later enable the iOS 17 foreground-instance path.
- The library itself starts at iOS 15. The included picker demo uses PhotosPicker on iOS 16 and later.

## Current scope

The package uses a subject layer over a repaired-looking blurred background. It does not reconstruct hidden geometry or guarantee clean results for large camera movements. The motion range is intentionally bounded.
