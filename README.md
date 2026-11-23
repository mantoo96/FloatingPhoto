# FloatingPhoto

[English](README.md) · [简体中文](README.zh-CN.md)

Turn a still image into a tilt-responsive SwiftUI photo with depth-based parallax, then export the same scene as an H.264 MP4.

FloatingPhoto is a native iOS Swift Package. It keeps the original photo visible while depth is prepared, reveals the interactive frame after the first successful render, and falls back to a static photo when a usable depth field is unavailable.

## Features

- SwiftUI preview with device-motion input or a fixed camera offset
- Continuous relative-depth rendering with Metal
- Depth Anything V2 Small on iOS 17 when the package is built with Swift 5.9 or later
- Vision-based foreground or person segmentation fallback
- Configurable camera travel, tilt sensitivity, crop, blur and depth strength
- Reduced Motion support with a centered preview
- Reusable preparation state shared by a preview and a video export
- H.264 MP4 export with a repeatable camera path
- Static-photo fallback for images without usable depth data

## Requirements

- iOS 15 or later
- Swift 5.7 or later
- A device or simulator with Metal support for the interactive renderer
- iOS 17 or later with a Swift 5.9 or later build for the bundled Depth Anything V2 Small model

The PhotosPicker demo requires iOS 16 or later because `PhotosPicker` was introduced in iOS 16.

## Installation

Add the package in Xcode with **File → Add Package Dependencies…** and enter your repository URL.

For a `Package.swift` dependency, replace the account name and version with the release you want to use:

```swift
dependencies: [
    .package(
        url: "https://github.com/<your-account>/FloatingPhoto.git",
        from: "1.0.0"
    )
]
```

Then add the `FloatingPhoto` product to your app target.

## Quick start

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

The view prepares the scene automatically. During preparation, the original image remains visible with the default progress indicator. When the first depth frame is presented, the cover fades away and the preview follows device tilt. Reduce Motion keeps the preview centered and reveals it immediately.

## Customize the status overlay

Use `statusOverlay` to provide your own loading, ready, degraded and failed states.

```swift
FloatingPhotoView(image: photo)
    .statusOverlay { phase in
        switch phase {
        case .idle, .processing:
            ProgressView("Preparing depth…")
                .padding()
                .background(.regularMaterial, in: Capsule())
        case .ready:
            EmptyView()
        case .degraded:
            Text("Still photo")
        case .failed:
            Text("Choose another photo")
        }
    }
```

`processing` remains visible until the first depth frame appears onscreen. A prepared scene can therefore be exportable before the preview reports `ready`.

The preparation phases are:

| Phase | Meaning |
| --- | --- |
| `.idle` | The scene has been created and has not started preparing. |
| `.processing` | Depth data and the renderer are being prepared, or the preview is waiting for its first frame. |
| `.ready` | A depth scene is available and its first frame has been presented. |
| `.degraded` | A static fallback is available because no usable depth field was produced. |
| `.failed` | The source image could not be prepared. |

## Share a scene with video export

Create one `FloatingPhotoScene` for a selected photo and configuration. Pass that instance to the view and reuse it for export.

```swift
import FloatingPhoto
import SwiftUI

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
    guard scene.canExport else { return }

    try await scene.exportVideo(
        to: file,
        size: CGSize(width: 1080, height: 1440),
        duration: 4,
        frameRate: 30
    )
}
```

Concurrent calls to `prepare()` share the same preparation work. A static fallback can also be exported. `exportVideo` replaces an existing file at the destination URL, so pass a local `.mp4` URL that your app owns.

## Motion and configuration

The default configuration is suitable for most photos. Use `.subtle` for a smaller camera movement and crop.

```swift
FloatingPhotoView(
    image: photo,
    configuration: .subtle,
    motion: .device
)
```

For previews, a fixed camera position is useful for screenshots and UI tests:

```swift
FloatingPhotoView(
    image: photo,
    motion: .staticOffset(x: 0.6, y: 0)
)
```

`intensity` controls maximum travel, `motionSensitivity` controls the response to small tilts, `backgroundScale` controls the centered crop, and the blur and depth properties shape the relief effect. Set `allowsDeviceMotion` to `false` when an app should never start motion updates.

## Depth processing

On iOS 17 and later, builds using Swift 5.9 or later can use the bundled Depth Anything V2 Small Core ML model for a continuous relative-depth field. Vision foreground segmentation provides a fallback on those systems. Earlier supported configurations use Vision person segmentation.

If depth preparation produces no usable field, the scene enters `.degraded`. The original image remains available as a still preview and can still be exported.

## Demo

Open [Demo/FloatingPhotoDemo.xcodeproj](Demo/FloatingPhotoDemo.xcodeproj) in Xcode. The demo uses `PhotosPicker`, shows photo-transfer and depth-preparation states, supports Reduce Motion, and demonstrates a fixed preview offset for repeatable Debug previews.

Before running the demo, select your own development team and bundle identifier in Xcode.

## Project structure

```text
Sources/FloatingPhoto/     Swift package
Tests/FloatingPhotoTests/ Package and renderer tests
Demo/FloatingPhotoDemo/    PhotosPicker demo app
```

## Attribution

The bundled Depth Anything V2 Small model is distributed under the Apache License 2.0. See the [model license](Sources/FloatingPhoto/Resources/DepthAnything-LICENSE.txt), the [Apple Core ML model catalog](https://developer.apple.com/machine-learning/models/), and the [Depth Anything V2 project](https://github.com/DepthAnything/Depth-Anything-V2).
