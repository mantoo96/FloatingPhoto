import FloatingPhoto
import PhotosUI
import SwiftUI

struct ContentView: View {
    var body: some View {
        if #available(iOS 16.0, *) {
            PhotoPickerDemo()
        } else {
            Text("This demo uses PhotosPicker on iOS 16 and later.")
                .padding()
        }
    }
}

@available(iOS 16.0, *)
private struct PhotoPickerDemo: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var photo: UIImage?

    var body: some View {
        NavigationView {
            Group {
                if let photo {
                    FloatingPhotoView(
                        image: photo,
                        configuration: .init(
                            intensity: 0.55,
                            maximumTilt: 0.22,
                            backgroundBlur: 5,
                            backgroundBlurOpacity: 0.22
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .padding()
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                        Text("Choose a photo")
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("FloatingPhoto")
            .toolbar {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label("Choose Photo", systemImage: "photo.badge.plus")
                }
            }
        }
        .task(id: selectedItem) {
            guard let selectedItem else { return }
            let data = try? await selectedItem.loadTransferable(type: Data.self)
            photo = data.flatMap(UIImage.init(data:))
        }
    }
}
