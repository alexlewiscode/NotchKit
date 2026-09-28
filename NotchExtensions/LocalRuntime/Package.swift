// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotchExtensionInstallation",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NotchExtensionInstallation", targets: ["NotchExtensionInstallation"]),
        .library(name: "NotchNativeExtensionRuntime", targets: ["NotchNativeExtensionRuntime"]),
        .executable(name: "notchkit-extension", targets: ["NotchExtensionTool"]),
        .executable(name: "notchkit-hub-validator", targets: ["HubArtifactValidator"]),
    ],
    dependencies: [
        .package(path: "../../NotchKit/Packages/NotchExtensionSDK"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.19"),
    ],
    targets: [
        .target(
            name: "NotchExtensionInstallation",
            dependencies: [
                .product(name: "NotchExtensionSDK", package: "NotchExtensionSDK"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            linkerSettings: [.linkedFramework("Security")]
        ),
        .target(
            name: "NotchNativeExtensionRuntime",
            dependencies: [
                "NotchExtensionInstallation",
                .product(name: "NotchExtensionSDK", package: "NotchExtensionSDK"),
                .product(name: "NotchExtensionWire", package: "NotchExtensionSDK"),
            ]
        ),
        .target(
            name: "NotchExtensionToolSupport",
            dependencies: [
                "NotchExtensionInstallation",
                .product(name: "NotchExtensionSDK", package: "NotchExtensionSDK"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ]
        ),
        .executableTarget(
            name: "NotchExtensionTool",
            dependencies: ["NotchExtensionToolSupport"]
        ),
        .executableTarget(
            name: "HubArtifactValidator",
            dependencies: [
                "NotchExtensionInstallation",
                .product(name: "NotchExtensionSDK", package: "NotchExtensionSDK"),
            ]
        ),
        .testTarget(
            name: "NotchExtensionInstallationTests",
            dependencies: [
                "NotchExtensionInstallation",
                "ZIPFoundation",
                .product(name: "NotchExtensionSDK", package: "NotchExtensionSDK"),
            ]
        ),
        .testTarget(
            name: "NotchNativeExtensionRuntimeTests",
            dependencies: [
                "NotchNativeExtensionRuntime",
                "NotchExtensionInstallation",
                .product(name: "NotchExtensionSDK", package: "NotchExtensionSDK"),
                .product(name: "NotchExtensionWire", package: "NotchExtensionSDK"),
            ]
        ),
        .testTarget(
            name: "NotchExtensionToolTests",
            dependencies: [
                "NotchExtensionToolSupport",
                "NotchExtensionInstallation",
                .product(name: "NotchExtensionSDK", package: "NotchExtensionSDK"),
            ]
        ),
    ]
)
