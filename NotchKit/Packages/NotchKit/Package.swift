// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotchKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "NotchAPI", targets: ["NotchAPI"]),
        .library(name: "NotchExtensions", targets: ["NotchExtensions"]),
    ],
    targets: [
        .target(name: "NotchAPI"),
        .target(name: "NotchExtensions", dependencies: ["NotchAPI"]),
        .testTarget(
            name: "NotchExtensionsTests",
            dependencies: ["NotchAPI", "NotchExtensions"]
        ),
    ]
)
