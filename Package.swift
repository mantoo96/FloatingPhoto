// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FloatingPhoto",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "FloatingPhoto",
            targets: ["FloatingPhoto"]
        )
    ],
    targets: [
        .target(
            name: "FloatingPhoto",
            path: "Sources/FloatingPhoto"
        ),
        .testTarget(
            name: "FloatingPhotoTests",
            dependencies: ["FloatingPhoto"],
            path: "Tests/FloatingPhotoTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
