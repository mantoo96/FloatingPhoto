# FloatingPhoto

[English](README.md) · [简体中文](README.zh-CN.md)

将静态图片转换为可响应倾斜操作的 SwiftUI 照片，通过深度实现视差效果，并将同一场景导出为 H.264 MP4 视频。

FloatingPhoto 是一个原生 iOS Swift Package。在准备深度数据期间，它会保持显示原始照片。首次成功渲染后才显示交互式画面。如果没有可用的深度场，则自动回退为静态照片。

## 功能

- 支持设备运动输入或固定相机偏移的 SwiftUI 预览
- 使用 Metal 连续渲染相对深度
- 在 iOS 17 上，使用 Swift 5.9 或更高版本构建时支持 Depth Anything V2 Small
- 基于 Vision 的前景或人物分割回退方案
- 可配置相机移动范围、倾斜灵敏度、裁剪、模糊和深度强度
- 支持“减弱动态效果”，并将预览保持在中心
- 预览和视频导出共享可复用的准备状态
- 使用可重复的相机路径导出 H.264 MP4 视频
- 对没有可用深度数据的图片提供静态照片回退

## 系统要求

- iOS 15 或更高版本
- Swift 5.7 或更高版本
- 设备或模拟器需要支持 Metal，才能使用交互式渲染器
- 使用 Swift 5.9 或更高版本构建，并运行在 iOS 17 或更高版本时，可使用内置的 Depth Anything V2 Small 模型

PhotosPicker 示例要求 iOS 16 或更高版本，因为 `PhotosPicker` 从 iOS 16 开始提供。

## 安装

在 Xcode 中选择 **File → Add Package Dependencies…**，然后输入仓库地址。

对于 `Package.swift` 依赖，请将账号名称和版本替换为你要使用的发行版本：

```swift
dependencies: [
    .package(
        url: "https://github.com/<your-account>/FloatingPhoto.git",
        from: "1.0.0"
    )
]
```

然后将 `FloatingPhoto` product 添加到你的 App target 中。

## 快速开始

```swift
import FloatingPhoto
import SwiftUI

struct PhotoCard: View {
    let photo: UIImage

    var body: some View {
        FloatingPhotoView(image: photo)
            .aspectRatio(photo.size, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}
```

视图会自动准备场景。在准备期间，默认进度指示器会叠加在原始图片上。首次深度画面显示后，遮罩会淡出，预览会跟随设备倾斜。开启“减弱动态效果”后，预览会保持居中并立即显示。

## 自定义状态叠加层

使用 `statusOverlay` 自定义加载中、就绪、降级和失败状态。

```swift
FloatingPhotoView(image: photo)
    .statusOverlay { phase in
        switch phase {
        case .idle, .processing:
            ProgressView("Preparing depth…")
                .padding()
                .background(.regularMaterial, in: Capsule())
        case .ready:
            EmptyView()
        case .degraded:
            Text("Still photo")
        case .failed:
            Text("Choose another photo")
        }
    }
```

在首个深度画面显示前，`processing` 状态会持续显示。因此，场景可能已经可以导出，而预览状态仍未报告为 `ready`。

准备阶段如下：

| 阶段 | 含义 |
| --- | --- |
| `.idle` | 场景已创建，但尚未开始准备。 |
| `.processing` | 正在准备深度数据和渲染器，或者预览正在等待首帧。 |
| `.ready` | 深度场景可用，并且首帧已经显示。 |
| `.degraded` | 没有生成可用的深度场，因此提供静态回退。 |
| `.failed` | 无法准备源图片。 |

## 通过视频导出分享场景

为选定的照片和配置创建一个 `FloatingPhotoScene`。将该实例传给视图，并复用它进行导出。

```swift
import FloatingPhoto
import SwiftUI

struct ShareableCard: View {
    @ObservedObject var scene: FloatingPhotoScene

    var body: some View {
        FloatingPhotoView(scene: scene)
            .aspectRatio(scene.image.size, contentMode: .fit)
    }
}

@MainActor
func exportMovie(for scene: FloatingPhotoScene, to file: URL) async throws {
    await scene.prepare()
    guard scene.canExport else { return }

    try await scene.exportVideo(
        to: file,
        size: CGSize(width: 1080, height: 1440),
        duration: 4,
        frameRate: 30
    )
}
```

并发调用 `prepare()` 会共享同一份准备工作。静态回退场景也可以导出。`exportVideo` 会替换目标 URL 上已有的文件，因此请传入 App 自己管理的本地 `.mp4` URL。

## 动态效果与配置

默认配置适用于大多数照片。使用 `.subtle` 可以减小相机移动范围和裁剪幅度。

```swift
FloatingPhotoView(
    image: photo,
    configuration: .subtle,
    motion: .device
)
```

对于预览，固定相机位置适合截图和 UI 测试：

```swift
FloatingPhotoView(
    image: photo,
    motion: .staticOffset(x: 0.6, y: 0)
)
```

`intensity` 控制最大移动范围，`motionSensitivity` 控制对轻微倾斜的响应，`backgroundScale` 控制居中裁剪，模糊和深度属性共同决定立体效果。如果 App 永远不应启动运动更新，请将 `allowsDeviceMotion` 设置为 `false`。

## 深度处理

在 iOS 17 及更高版本上，使用 Swift 5.9 或更高版本构建时，可以使用内置的 Depth Anything V2 Small Core ML 模型生成连续的相对深度场。在这些系统上，Vision 前景分割提供回退方案。其他受支持的配置使用 Vision 人物分割。

如果深度准备没有生成可用的深度场，场景会进入 `.degraded`。原始图片仍可作为静态预览使用，也可以继续导出。

## 示例

在 Xcode 中打开 [Demo/FloatingPhotoDemo.xcodeproj](Demo/FloatingPhotoDemo.xcodeproj)。示例使用 `PhotosPicker`，展示照片传输和深度准备状态，支持“减弱动态效果”，并演示可重复 Debug 预览的固定偏移。

运行示例前，请在 Xcode 中选择你自己的开发团队和 Bundle Identifier。

## 项目结构

```text
Sources/FloatingPhoto/     Swift package
Tests/FloatingPhotoTests/  Package 和渲染器测试
Demo/FloatingPhotoDemo/    PhotosPicker 示例 App
```

## 鸣谢

内置的 Depth Anything V2 Small 模型遵循 Apache License 2.0 发布。请参阅[模型许可证](Sources/FloatingPhoto/Resources/DepthAnything-LICENSE.txt)、[Apple Core ML 模型目录](https://developer.apple.com/machine-learning/models/)和 [Depth Anything V2 项目](https://github.com/DepthAnything/Depth-Anything-V2)。
