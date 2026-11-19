import FloatingPhoto
import PhotosUI
import SwiftUI

struct ContentView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var photo: UIImage?

    var body: some View {
        NavigationStack {
            Group {
                if let photo {
                    FloatingPhotoView(
                        image: photo,
                        configuration: .init(
                            intensity: 0.75,
                            backgroundBlur: 6,
                            maximumTilt: 0.1
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .padding()
                } else {
                    ContentUnavailableView(
                        "Choose a photo",
                        systemImage: "photo",
                        description: Text("The photo stays on device while the scene is prepared.")
                    )
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
            photo = try? await selectedItem.loadTransferable(type: Data.self).flatMap(UIImage.init)
        }
    }
}
