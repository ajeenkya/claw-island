// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "clawIsland",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "clawIsland",
            path: "Sources/clawIsland",
            resources: [.copy("../../Resources/Info.plist")]
        ),
        .testTarget(
            name: "clawIslandTests",
            dependencies: ["clawIsland"],
            path: "Tests/clawIslandTests"
        )
    ]
)
