import FloatingPhoto
import PhotosUI
import SwiftUI

struct ContentView: View {
    var body: some View {
        if #available(iOS 16.0, *) {
            PhotoPickerDemo()
        } else {
            Text("此演示的照片选择器需要 iOS 16 或更高版本。")
                .padding()
        }
    }
}

@available(iOS 16.0, *)
private struct PhotoPickerDemo: View {
    private enum TransferPhase { case idle, reading, failed }

    @State private var selectedItem: PhotosPickerItem?
    @State private var scene: FloatingPhotoScene?
    @State private var transfer: TransferPhase = .idle

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
                if let scene {
                    FloatingPhotoView(scene: scene, motion: previewMotion)
                        .statusOverlay { phase in
                            status(for: phase)
                                .padding(12)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        }
                        .aspectRatio(scene.image.size.width / max(1, scene.image.size.height), contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .padding()
                } else if transfer != .idle {
                    transferStatus
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo").font(.largeTitle)
                        Text("选择一张照片")
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("FloatingPhoto")
            .toolbar {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label("选择照片", systemImage: "photo.badge.plus")
                }
            }
        }
#if DEBUG
        .onAppear {
            if scene == nil, ProcessInfo.processInfo.arguments.contains("--preview-photo") {
                let file = FileManager.default.temporaryDirectory.appendingPathComponent("FloatingPhotoPreview.jpg")
                if let image = UIImage(contentsOfFile: file.path) { scene = FloatingPhotoScene(image: image) }
            }
        }
#endif
        .task(id: selectedItem) {
            guard let item = selectedItem else { return }
            transfer = .reading
            do {
                let data = try await item.loadTransferable(type: Data.self)
                try Task.checkCancellation()
                guard let data, let photo = UIImage(data: data) else { throw FloatingPhotoError.invalidImage }
                scene = FloatingPhotoScene(image: photo)
                transfer = .idle
            } catch {
                guard !Task.isCancelled else { return }
                transfer = .failed
                selectedItem = nil // Selecting the same item again should retry the transfer.
            }
        }
    }

    @ViewBuilder private var transferStatus: some View {
        switch transfer {
        case .reading: StatusBadge(text: "正在读取照片…")
        case .failed: StatusBadge(text: "照片读取失败，请重新选择", icon: "exclamationmark.circle")
        case .idle: EmptyView()
        }
    }

    @ViewBuilder private func status(for phase: FloatingPhotoPhase) -> some View {
        if transfer == .idle {
            PreviewStatus(phase: phase, followsTilt: previewMotion == .device)
        } else {
            transferStatus
        }
    }
}

private struct PreviewStatus: View {
    let phase: FloatingPhotoPhase
    let followsTilt: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var hintDismissed = false

    var body: some View {
        Group {
            switch phase {
            case .idle, .processing:
                StatusBadge(text: "正在生成景深…")
            case .ready:
                if !hintDismissed {
                    StatusBadge(text: followsTilt && !reduceMotion ? "轻轻倾斜手机" : "照片已就绪", icon: "checkmark.circle")
                }
            case .degraded:
                StatusBadge(text: "景深不可用，已显示原图", icon: "photo")
            case .failed:
                StatusBadge(text: "无法生成预览，请重新选择", icon: "exclamationmark.circle")
            }
        }
        .task(id: phase) {
            hintDismissed = false
            guard phase == .ready, !voiceOver else { return }
            do { try await Task.sleep(nanoseconds: 2_500_000_000) } catch { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { hintDismissed = true }
        }
    }
}

private struct StatusBadge: View {
    let text: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon).accessibilityHidden(true)
            } else {
                ProgressView().accessibilityHidden(true)
            }
            Text(text)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}
