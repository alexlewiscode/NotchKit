// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotchExtensionValidation",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ValidationCore", targets: ["ValidationCore"]),
        .executable(name: "ext-validate", targets: ["ext-validate"]),
    ],
    dependencies: [
        .package(path: "../../NotchKit/Packages/NotchExtensionSDK")
    ],
    targets: [
        .target(
            name: "ValidationCore",
            dependencies: [
                .product(name: "NotchExtensionSDK", package: "NotchExtensionSDK")
            ]
        ),
        .executableTarget(
            name: "ext-validate",
            dependencies: [
                "ValidationCore",
                .product(name: "NotchExtensionSDK", package: "NotchExtensionSDK"),
            ]
        ),
        .testTarget(
            name: "ValidationCoreTests",
            dependencies: [
                "ValidationCore",
                .product(name: "NotchExtensionSDK", package: "NotchExtensionSDK"),
            ]
        ),
    ]
)
