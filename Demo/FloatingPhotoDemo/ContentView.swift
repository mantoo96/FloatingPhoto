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

    private var previewMotion: FloatingPhotoMotion {
#if DEBUG
        let process = ProcessInfo.processInfo
        if process.arguments.contains("--preview-photo"),
           let text = process.environment["FLOATING_PHOTO_PREVIEW_X"], let value = Double(text), value.isFinite {
            return .staticOffset(x: CGFloat(value), y: 0)
        }
#endif
        return .device
    }

    var body: some View {
        NavigationView {
            Group {
                if let photo {
                    FloatingPhotoView(image: photo, motion: previewMotion)
                        .aspectRatio(photo.size.width / max(1, photo.size.height), contentMode: .fit)
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
#if DEBUG
        .onAppear {
            if photo == nil, ProcessInfo.processInfo.arguments.contains("--preview-photo") {
                let file = FileManager.default.temporaryDirectory.appendingPathComponent("FloatingPhotoPreview.jpg")
                photo = UIImage(contentsOfFile: file.path)
            }
        }
#endif
        .task(id: selectedItem) {
            guard let selectedItem else { return }
            let data = try? await selectedItem.loadTransferable(type: Data.self)
            guard !Task.isCancelled else { return }
            photo = data.flatMap(UIImage.init(data:))
        }
    }
}
