// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AudioGenCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "AudioGenCore", targets: ["AudioGenCore"]),
    ],
    targets: [
        .target(name: "AudioGenCore"),
        .testTarget(
            name: "AudioGenCoreTests",
            dependencies: ["AudioGenCore"]
        ),
    ]
)
