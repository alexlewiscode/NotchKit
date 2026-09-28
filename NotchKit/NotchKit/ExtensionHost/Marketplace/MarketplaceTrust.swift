import Foundation
import NotchExtensionSDK
import NotchExtensionWire

struct MarketplaceHostEnvironment: Sendable {
    let macOSVersion: ExtensionVersion
    let hostVersion: ExtensionVersion
    let sdkVersion: ExtensionVersion
    let protocolVersion: Int
    let architecture: ExtensionArchitecture

    static func current(hostVersion: ExtensionVersion) -> Self {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let architecture = ExtensionArchitecture.arm64
        #else
        let architecture = ExtensionArchitecture.x86_64
        #endif
        return Self(
            macOSVersion: ExtensionVersion(major: os.majorVersion, minor: os.minorVersion, patch: os.patchVersion),
            hostVersion: hostVersion,
            sdkVersion: ExtensionVersion(
                major: ExtensionAPIVersion.current.major,
                minor: ExtensionAPIVersion.current.minor,
                patch: ExtensionAPIVersion.current.patch
            ),
            protocolVersion: ExtensionWireProtocol.currentVersion,
            architecture: architecture
        )
    }
}

enum MarketplaceCompatibilityState: Equatable, Sendable {
    case compatible
    case incompatible(String)
}

enum MarketplaceTrustState: Equatable, Sendable {
    case trusted
    case untrusted(String)
}

enum MarketplaceReleaseEvaluator {
    static func compatibility(
        of release: MarketplaceRelease,
        with environment: MarketplaceHostEnvironment
    ) -> MarketplaceCompatibilityState {
        let compatibility = release.compatibility
        guard environment.macOSVersion >= compatibility.minimumMacOSVersion else {
            return .incompatible("Requires macOS \(compatibility.minimumMacOSVersion) or later.")
        }
        guard compatibility.supportedHostVersions.contains(environment.hostVersion) else {
            return .incompatible("This version of NotchKit is not supported.")
        }
        guard compatibility.supportedSDKVersions.contains(environment.sdkVersion),
              compatibility.apiVersion.major == environment.sdkVersion.major
        else { return .incompatible("This extension uses an unsupported SDK version.") }
        guard (compatibility.protocolVersions.minimum ... compatibility.protocolVersions.maximum)
            .contains(environment.protocolVersion)
        else { return .incompatible("This extension uses an unsupported protocol version.") }
        guard compatibility.supportedArchitectures.contains(environment.architecture) else {
            return .incompatible("This extension does not support this Mac's architecture.")
        }
        return .compatible
    }

    static func trust(of entry: MarketplaceCatalogEntry) -> MarketplaceTrustState {
        guard entry.latest.trustBadges.contains(.reviewedSafe) else {
            return .untrusted("This release has not been reviewed and marked safe by NotchKit.")
        }
        guard !entry.latest.teamIdentifier.isEmpty else {
            return .untrusted("The release has no trusted signing team.")
        }
        if entry.latest.trustBadges.contains(.appleDeveloper), entry.latest.signerType != .developerID {
            return .untrusted("The Apple Developer badge does not match the release signer.")
        }
        return .trusted
    }
}
