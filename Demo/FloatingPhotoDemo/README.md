# FloatingPhoto Demo

Open `FloatingPhotoDemo.xcodeproj` in Xcode to run the demo app.

The demo is configured with the FloatingPhoto demo signing identity:

- Bundle identifier: `com.example.FloatingPhotoDemo`
- Development team: `your-team-id`
- Minimum iOS: 16.0 because the picker uses `PhotosPicker`

The demo links the local `FloatingPhoto` Swift package from the parent directory. Installing it with this bundle identifier replaces the app already installed under the FloatingPhoto demo bundle identifier.

For a repeatable Debug preview, copy your own JPEG into the app container at `tmp/FloatingPhotoPreview.jpg` and launch with `--preview-photo`. The optional launch environment variable `FLOATING_PHOTO_PREVIEW_X` fixes the horizontal camera position between `-1` and `1`. Omitting it enables the motion sensor. The normal picker opens on a regular launch.
