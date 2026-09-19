import ExtensionFoundation
import NotchExtensionInstallation
import NotchExtensionSDK

public struct NativeExtensionIdentityDescriptor: Equatable, Hashable, Sendable {
    public let id: String
    public let bundleIdentifier: String
    public let extensionPointIdentifier: String
    public let localizedName: String

    public init(
        id: String,
        bundleIdentifier: String,
        extensionPointIdentifier: String,
        localizedName: String = ""
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.extensionPointIdentifier = extensionPointIdentifier
        self.localizedName = localizedName
    }
}

public struct NativeExtensionInstallCandidate: Sendable {
    public let record: InstalledExtensionRecord
    public let manifest: ExtensionPackageManifest

    public init(record: InstalledExtensionRecord, manifest: ExtensionPackageManifest) {
        self.record = record
        self.manifest = manifest
    }
}

public struct NativeExtensionMatch: Sendable {
    public let record: InstalledExtensionRecord
    public let manifest: ExtensionPackageManifest
    public let identity: NativeExtensionIdentityDescriptor
}

public enum NativeExtensionMatchingError: Error, Equatable {
    case recordManifestMismatch(ExtensionIdentity)
    case invalidArtifact(ExtensionIdentity)
    case ambiguousIdentity(ExtensionIdentity)
    case identityMismatch(ExtensionIdentity)
}

public enum NativeExtensionMatcher {
    public static func match(
        candidates: [NativeExtensionInstallCandidate],
        identities: [NativeExtensionIdentityDescriptor]
    ) throws -> [NativeExtensionMatch] {
        try candidates.compactMap { candidate in
            guard candidate.record.id == candidate.manifest.metadata.id else {
                throw NativeExtensionMatchingError.recordManifestMismatch(candidate.record.id)
            }
            guard let artifact = candidate.manifest.artifact.appExtension,
                  candidate.record.extensionBundleIdentifiers.contains(artifact.extensionBundleIdentifier)
            else {
                throw NativeExtensionMatchingError.invalidArtifact(candidate.record.id)
            }
            let matches = identities.filter {
                $0.bundleIdentifier == artifact.extensionBundleIdentifier
                    && $0.extensionPointIdentifier == artifact.extensionPointIdentifier
            }
            guard matches.count <= 1 else {
                throw NativeExtensionMatchingError.ambiguousIdentity(candidate.record.id)
            }
            return matches.first.map {
                NativeExtensionMatch(record: candidate.record, manifest: candidate.manifest, identity: $0)
            }
        }
    }

    @available(macOS 26.0, *)
    public static func descriptor(for identity: AppExtensionIdentity) -> NativeExtensionIdentityDescriptor {
        NativeExtensionIdentityDescriptor(
            id: identity.id,
            bundleIdentifier: identity.bundleIdentifier,
            extensionPointIdentifier: identity.extensionPointIdentifier,
            localizedName: identity.localizedName
        )
    }

    @available(macOS 26.0, *)
    public static func validate(
        identity: AppExtensionIdentity,
        manifest: ExtensionPackageManifest
    ) throws {
        guard let artifact = manifest.artifact.appExtension,
              identity.bundleIdentifier == artifact.extensionBundleIdentifier,
              identity.extensionPointIdentifier == artifact.extensionPointIdentifier
        else { throw NativeExtensionMatchingError.identityMismatch(manifest.metadata.id) }
    }
}
