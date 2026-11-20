# FloatingPhoto Demo

Open `FloatingPhotoDemo.xcodeproj` in Xcode to run the demo app.

The demo is configured with the FloatingPhoto demo signing identity:

- Bundle identifier: `com.example.FloatingPhotoDemo`
- Development team: `your-team-id`
- Minimum iOS: 16.0 because the picker uses `PhotosPicker`

The demo links the local `FloatingPhoto` Swift package from the parent directory. Installing it with this bundle identifier replaces the app already installed under the FloatingPhoto demo bundle identifier.

Choose a photo to see the picker transfer, depth preparation, and first interactive frame. The demo keeps the current card visible when reading a replacement photo. `ContentView.swift` uses `FloatingPhotoView(scene:)` and `statusOverlay` to show each stage and briefly invite the user to tilt the phone. Reduce Motion uses a neutral ready message. An unavailable depth effect leaves a labeled still photo.

For a repeatable Debug preview, copy your own JPEG into the app container at `tmp/FloatingPhotoPreview.jpg` and launch with `--preview-photo`. The optional launch environment variable `FLOATING_PHOTO_PREVIEW_X` fixes the horizontal camera position between `-1` and `1`. Omitting it enables the motion sensor. The normal picker opens on a regular launch.
