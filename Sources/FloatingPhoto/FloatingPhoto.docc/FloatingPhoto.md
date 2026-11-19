# FloatingPhoto

Turn an ordinary photo into a bounded motion-parallax scene with a SwiftUI view.

## Overview

`FloatingPhotoView` is the fast path for showing a scene. `FloatingPhotoScene` is useful when the host app needs to prepare once and export the result as a video.

The package uses foreground instance masks on iOS 17 and later. On iOS 15 and 16 it uses Vision's person-segmentation request. If segmentation is unavailable or produces no usable result, the scene falls back to a gentle whole-image animation.

## Topics

### Showing a scene

- ``FloatingPhotoView``
- ``FloatingPhotoConfiguration``

### Preparing and exporting

- ``FloatingPhotoScene``
- ``FloatingPhotoPhase``
- ``FloatingPhotoError``
