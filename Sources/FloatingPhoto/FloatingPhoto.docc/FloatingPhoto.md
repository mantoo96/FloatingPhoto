# FloatingPhoto

Turn an ordinary photo into a bounded motion-parallax scene with a SwiftUI view.

## Overview

`FloatingPhotoView` is the fast path for showing a scene. `FloatingPhotoScene` is useful when the host app needs to prepare once and export the result as a video.

Vision extracts a foreground subject on supported iOS versions. The renderer keeps the complete photo as a stable background, adds a restrained blur layer, and moves the extracted subject independently. A low-opacity white edge haze gives the cutout a soft depth boundary. The same composition is used for live rendering and video export.

The package targets iOS 15 and Swift 5.7 or later. iOS 17 and later use foreground instance masks for people, pets, and other noticeable objects. Earlier systems use person segmentation. When extraction is unavailable, the scene keeps a simpler complete-photo motion result.

## Topics

### Showing a scene

- ``FloatingPhotoView``
- ``FloatingPhotoConfiguration``

### Preparing and exporting

- ``FloatingPhotoScene``
- ``FloatingPhotoPhase``
- ``FloatingPhotoError``
