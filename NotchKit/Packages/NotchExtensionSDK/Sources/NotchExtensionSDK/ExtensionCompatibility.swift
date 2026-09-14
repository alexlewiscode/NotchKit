//
//  ExtensionCompatibility.swift
//  NotchExtensionSDK
//
//  Compatibility checks beyond matching the major API version only.
//

import Foundation

/// Reasons a manifest cannot run against the host.
public enum ExtensionCompatibilityError: Error, Equatable {
    /// The host does not support this delivery/execution kind yet.
    case unsupportedArtifactKind(ExtensionIdentity, ExtensionArtifactKind)
    /// The running host version is outside the declared supported range.
    case unsupportedHostVersion(
        ExtensionIdentity,
        required: ExtensionVersionRange,
        running: ExtensionVersion
    )
    /// The running SDK version is outside the declared supported range.
    case unsupportedSDKVersion(
        ExtensionIdentity,
        required: ExtensionVersionRange,
        running: ExtensionAPIVersion
    )
    /// An entry point uses a capability that was not declared.
    case undeclaredCapability(ExtensionIdentity, ExtensionCapability)
    /// A declared capability has no matching entry point.
    case capabilityWithoutEntryPoint(ExtensionIdentity, ExtensionCapability)
    /// Two entry points share an identity.
    case duplicateEntryPoint(ExtensionIdentity, id: String)
}

/// Validates a manifest against the running host and SDK.
public enum ExtensionCompatibility {
    /// Artifact kinds this host build can actually run.
    ///
    /// Only statically linked first-party code runs today. The out-of-process
    /// kinds stay unsupported until a runnable prototype provides evidence.
    public static let supportedArtifactKinds: Set<ExtensionArtifactKind> = [.compiledIn]

    /// Validates `metadata` against the running host and SDK versions.
    ///
    /// - Parameters:
    ///   - hostedVersion: the running host application version.
    ///   - sdkVersion: the running SDK/API version, defaulting to the current.
    public static func validate(
        _ metadata: ExtensionMetadata,
        hostVersion: ExtensionVersion,
        sdkVersion: ExtensionAPIVersion = .current
    ) throws {
        guard supportedArtifactKinds.contains(metadata.artifactKind) else {
            throw ExtensionCompatibilityError.unsupportedArtifactKind(
                metadata.id, metadata.artifactKind
            )
        }

        guard metadata.supportedHostVersions.contains(hostVersion) else {
            throw ExtensionCompatibilityError.unsupportedHostVersion(
                metadata.id,
                required: metadata.supportedHostVersions,
                running: hostVersion
            )
        }

        let runningSDK = ExtensionVersion(
            major: sdkVersion.major, minor: sdkVersion.minor, patch: sdkVersion.patch
        )
        guard metadata.supportedSDKVersions.contains(runningSDK) else {
            throw ExtensionCompatibilityError.unsupportedSDKVersion(
                metadata.id,
                required: metadata.supportedSDKVersions,
                running: sdkVersion
            )
        }

        var seenEntryPointIDs = Set<String>()
        var requiredCapabilities = Set<ExtensionCapability>()
        for entryPoint in metadata.entryPoints {
            guard seenEntryPointIDs.insert(entryPoint.id).inserted else {
                throw ExtensionCompatibilityError.duplicateEntryPoint(
                    metadata.id, id: entryPoint.id
                )
            }
            let capability = entryPoint.kind.requiredCapability
            requiredCapabilities.insert(capability)
            guard metadata.capabilities.contains(capability) else {
                throw ExtensionCompatibilityError.undeclaredCapability(
                    metadata.id, capability
                )
            }
        }

        for capability in metadata.capabilities where !requiredCapabilities.contains(capability) {
            throw ExtensionCompatibilityError.capabilityWithoutEntryPoint(
                metadata.id, capability
            )
        }
    }
}
