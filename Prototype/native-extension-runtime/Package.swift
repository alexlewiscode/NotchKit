// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NativeExtensionPrototype",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "NativeExtensionShared", targets: ["NativeExtensionShared"]),
        .executable(name: "notch-extension-package", targets: ["NotchExtensionPackageTool"]),
    ],
    targets: [
        .target(name: "NativeExtensionShared"),
        .executableTarget(
            name: "NotchExtensionPackageTool",
            dependencies: ["NativeExtensionShared"]
        ),
        .testTarget(
            name: "NativeExtensionSharedTests",
            dependencies: ["NativeExtensionShared"]
        ),
    ]
)
