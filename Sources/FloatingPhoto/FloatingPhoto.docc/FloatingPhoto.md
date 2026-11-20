# FloatingPhoto

Turn an ordinary photo into a bounded motion-parallax scene with a SwiftUI view.

## Overview

`FloatingPhotoView` is the fast path for showing a scene. `FloatingPhotoScene` is useful when the host app needs to prepare once and export the result as a video.

On iOS 17 and later, modern toolchains bundle a Core ML model that estimates relative depth. The interactive view and video exporter project one textured surface through the same camera. Earlier systems use a Vision person mask as a depth estimate. Unusable depth falls back to gentle whole-photo motion.

## Topics

### Showing a scene

- ``FloatingPhotoView``
- ``FloatingPhotoConfiguration``

### Preparing and exporting

- ``FloatingPhotoScene``
- ``FloatingPhotoPhase``
- ``FloatingPhotoError``
