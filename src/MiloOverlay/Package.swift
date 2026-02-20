// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MiloOverlay",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MiloOverlay",
            path: "Sources/MiloOverlay",
            resources: [.copy("../../Resources/Info.plist")]
        ),
        .testTarget(
            name: "MiloOverlayTests",
            dependencies: ["MiloOverlay"],
            path: "Tests/MiloOverlayTests"
        )
    ]
)
