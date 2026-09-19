// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotchExtensionSDK",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "NotchExtensionSDK", targets: ["NotchExtensionSDK"]),
        .library(name: "NotchExtensionRuntime", targets: ["NotchExtensionRuntime"]),
        .library(name: "NotchExtensionWire", targets: ["NotchExtensionWire"]),
    ],
    targets: [
        .target(name: "NotchExtensionSDK"),
        .target(name: "NotchExtensionRuntime", dependencies: ["NotchExtensionSDK"]),
        .target(name: "NotchExtensionWire", dependencies: ["NotchExtensionSDK"]),
        .testTarget(
            name: "NotchExtensionRuntimeTests",
            dependencies: ["NotchExtensionSDK", "NotchExtensionRuntime"]
        ),
        .testTarget(
            name: "NotchExtensionContractTests",
            dependencies: ["NotchExtensionSDK", "NotchExtensionWire"]
        ),
    ]
)
