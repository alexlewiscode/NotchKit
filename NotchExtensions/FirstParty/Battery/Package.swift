// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotchBatteryExtension",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "BatteryExtension", targets: ["BatteryExtension"]),
    ],
    dependencies: [
        .package(path: "../../../NotchKit/Packages/NotchExtensionSDK"),
    ],
    targets: [
        .target(
            name: "BatteryExtension",
            dependencies: [
                .product(name: "NotchExtensionSDK", package: "NotchExtensionSDK"),
            ]
        ),
        .testTarget(
            name: "BatteryExtensionTests",
            dependencies: [
                "BatteryExtension",
                .product(name: "NotchExtensionSDK", package: "NotchExtensionSDK"),
            ]
        ),
    ]
)