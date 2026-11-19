# FloatingPhoto demo app

Create an iOS App target in Xcode and add the local package at the repository root. The smallest demo is:

```swift
import FloatingPhoto
import SwiftUI

struct ContentView: View {
    let image: UIImage

    var body: some View {
        FloatingPhotoView(image: image)
            .ignoresSafeArea()
    }
}
```
