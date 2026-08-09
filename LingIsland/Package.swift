// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LingIsland",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "LingIsland",
            path: "Sources/LingIsland"
        ),
        .executableTarget(
            name: "MediaRemoteAdapter",
            path: "Sources/MediaRemoteAdapter"
        )
    ]
)
