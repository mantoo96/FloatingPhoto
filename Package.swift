// swift-tools-version: 5.7
import PackageDescription

// Older Core ML compilers cannot process the iOS 17 model specification.
#if compiler(>=5.9)
let modelResources: [Resource] = [.process("Resources/DepthAnythingV2SmallF16P6.mlpackage")]
let excludedModels: [String] = []
#else
let modelResources: [Resource] = []
let excludedModels = ["Resources/DepthAnythingV2SmallF16P6.mlpackage"]
#endif

let package = Package(
    name: "FloatingPhoto",
    platforms: [.iOS(.v15)],
    products: [.library(name: "FloatingPhoto", targets: ["FloatingPhoto"])],
    targets: [
        .target(
            name: "FloatingPhoto",
            exclude: excludedModels,
            resources: modelResources + [.copy("Resources/DepthAnything-LICENSE.txt"), .copy("Resources/PhotoSurface.metal")]
        ),
        .testTarget(name: "FloatingPhotoTests", dependencies: ["FloatingPhoto"])
    ],
    swiftLanguageVersions: [.v5]
)
