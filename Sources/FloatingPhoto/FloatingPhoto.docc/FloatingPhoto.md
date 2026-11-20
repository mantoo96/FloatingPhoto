# ``FloatingPhoto``

Display a depth-responsive photo in SwiftUI and export the same scene to a movie.

## Overview

Use ``FloatingPhotoView/init(image:configuration:motion:)`` to display one photo. The original image and a progress indicator stay onscreen during depth estimation. The cover fades when the first depth frame appears. Reduce Motion uses a centered view and an immediate reveal. The package targets iOS 15 and Swift 5.7 or later.

### Present your own status

Use ``FloatingPhotoView/statusOverlay(_:)`` to replace the progress indicator. This closure receives the phase of the visible preview. A ready scene can still have a `.processing` overlay while its first frame is being presented. A `.degraded` preview displays the static photo.

```swift
FloatingPhotoView(image: photo)
    .statusOverlay { phase in
        if phase == .idle || phase == .processing {
            ProgressView("Preparing depth…")
        }
    }
```

### Reuse a scene

Create one ``FloatingPhotoScene`` when a photo is selected. Pass it to ``FloatingPhotoView/init(scene:motion:)`` and observe ``FloatingPhotoScene/phase`` on the main actor. The view starts preparation automatically. Concurrent calls to ``FloatingPhotoScene/prepare()`` share the same work.

Use ``FloatingPhotoScene/canExport`` to enable an export action for both a depth scene and a static fallback. To export without displaying a view, prepare the scene explicitly.

```swift
let scene = FloatingPhotoScene(image: photo)
await scene.prepare()
try await scene.exportVideo(to: fileURL, size: CGSize(width: 1080, height: 1440))
```

## Topics

### Showing a photo

- ``FloatingPhotoView``
- ``FloatingPhotoMotion``
- ``FloatingPhotoConfiguration``

### Preparing and exporting

- ``FloatingPhotoScene``
- ``FloatingPhotoPhase``
- ``FloatingPhotoError``
