//
//  ExtensionPackageManifest.swift
//  NotchExtensionSDK
//

import Foundation

/// The schema-v2 envelope used by independently delivered extension packages.
///
/// `metadata` deliberately retains the Tier A contract unchanged. Package-only
/// execution and privilege declarations live beside it.
public struct ExtensionPackageManifest: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let metadata: ExtensionMetadata
    public let artifact: ExtensionPackageArtifact
    public let permissions: Set<ExtensionDeclaredPermission>
    public let hostActions: Set<ExtensionHostAction>
    public let entryPoints: [ExtensionPackageEntryPoint]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        metadata: ExtensionMetadata,
        artifact: ExtensionPackageArtifact,
        permissions: Set<ExtensionDeclaredPermission> = [],
        hostActions: Set<ExtensionHostAction> = [],
        entryPoints: [ExtensionPackageEntryPoint]
    ) {
        self.schemaVersion = schemaVersion
        self.metadata = metadata
        self.artifact = artifact
        self.permissions = permissions
        self.hostActions = hostActions
        self.entryPoints = entryPoints
    }
}

/// Package-level execution metadata. App-extension details are required only
/// when `kind` is `.appExtension`.
public struct ExtensionPackageArtifact: Codable, Hashable, Sendable {
    public let kind: ExtensionArtifactKind
    public let appExtension: AppExtensionArtifactMetadata?

    public init(
        kind: ExtensionArtifactKind,
        appExtension: AppExtensionArtifactMetadata? = nil
    ) {
        self.kind = kind
        self.appExtension = appExtension
    }
}

/// Discovery and compatibility metadata for an ExtensionKit app extension.
public struct AppExtensionArtifactMetadata: Codable, Hashable, Sendable {
    public let providerBundleIdentifier: String
    public let extensionBundleIdentifier: String
    public let extensionPointIdentifier: String
    public let minimumMacOSVersion: ExtensionVersion
    public let protocolVersions: ExtensionProtocolVersionRange
    public let architectures: Set<ExtensionArchitecture>

    public init(
        providerBundleIdentifier: String,
        extensionBundleIdentifier: String,
        extensionPointIdentifier: String,
        minimumMacOSVersion: ExtensionVersion,
        protocolVersions: ExtensionProtocolVersionRange,
        architectures: Set<ExtensionArchitecture>
    ) {
        self.providerBundleIdentifier = providerBundleIdentifier
        self.extensionBundleIdentifier = extensionBundleIdentifier
        self.extensionPointIdentifier = extensionPointIdentifier
        self.minimumMacOSVersion = minimumMacOSVersion
        self.protocolVersions = protocolVersions
        self.architectures = architectures
    }
}

/// An inclusive range of integer wire protocol versions.
public struct ExtensionProtocolVersionRange: Codable, Hashable, Sendable {
    public let minimum: Int
    public let maximum: Int

    public init(minimum: Int, maximum: Int) {
        self.minimum = minimum
        self.maximum = maximum
    }

    public func contains(_ version: Int) -> Bool {
        version >= minimum && version <= maximum
    }
}

/// CPU architectures an extension package may carry.
public enum ExtensionArchitecture: String, Codable, CaseIterable, Sendable {
    case arm64
    case x86_64
}

/// Presentation ownership for a package entry point.
public enum ExtensionEntryPointPresentationMode: String, Codable, CaseIterable, Sendable {
    case remoteScene = "remote-scene"
    case declarative
}

/// Package-specific entry-point information kept separate from the stable Tier
/// A `ExtensionEntryPoint` encoding.
public struct ExtensionPackageEntryPoint: Codable, Hashable, Identifiable, Sendable {
    public var id: String { entryPoint.id }

    public let entryPoint: ExtensionEntryPoint
    public let presentationMode: ExtensionEntryPointPresentationMode
    public let sceneName: String?

    public init(
        entryPoint: ExtensionEntryPoint,
        presentationMode: ExtensionEntryPointPresentationMode,
        sceneName: String? = nil
    ) {
        self.entryPoint = entryPoint
        self.presentationMode = presentationMode
        self.sceneName = sceneName
    }
}

/// A permission disclosure, including who obtains it and the localized usage
/// description shown to the user.
public struct ExtensionDeclaredPermission: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case accessibility
        case mediaControl = "media-control"
        case camera
        case screenRecording = "screen-recording"
    }

    public enum Owner: String, Codable, CaseIterable, Sendable {
        case host
        case `extension`
    }

    public let kind: Kind
    public let required: Bool
    public let owner: Owner
    public let usageDescriptionKey: String

    public init(
        kind: Kind,
        required: Bool,
        owner: Owner,
        usageDescriptionKey: String
    ) {
        self.kind = kind
        self.required = required
        self.owner = owner
        self.usageDescriptionKey = usageDescriptionKey
    }

    public static func accessibility(
        required: Bool = true,
        owner: Owner = .host,
        usageDescriptionKey: String
    ) -> Self {
        Self(kind: .accessibility, required: required, owner: owner, usageDescriptionKey: usageDescriptionKey)
    }

    public static func mediaControl(
        required: Bool = true,
        owner: Owner = .host,
        usageDescriptionKey: String
    ) -> Self {
        Self(kind: .mediaControl, required: required, owner: owner, usageDescriptionKey: usageDescriptionKey)
    }

    public static func camera(
        required: Bool = true,
        owner: Owner = .extension,
        usageDescriptionKey: String
    ) -> Self {
        Self(kind: .camera, required: required, owner: owner, usageDescriptionKey: usageDescriptionKey)
    }

    public static func screenRecording(
        required: Bool = true,
        owner: Owner = .extension,
        usageDescriptionKey: String
    ) -> Self {
        Self(kind: .screenRecording, required: required, owner: owner, usageDescriptionKey: usageDescriptionKey)
    }
}

/// Host-owned effects an extension may request over the wire.
public enum ExtensionHostAction: String, Codable, CaseIterable, Sendable {
    case openDestination = "open-destination"
    case closeNotch = "close-notch"
    case showSneakPeek = "show-sneak-peek"
    case hideSneakPeek = "hide-sneak-peek"
}

public enum ExtensionPackageManifestValidationError: Error, Equatable, LocalizedError {
    case unsupportedSchemaVersion(Int)
    case artifactKindMismatch
    case invalidSource(ExtensionSource)
    case missingAppExtensionMetadata
    case unexpectedAppExtensionMetadata
    case unsupportedMinimumMacOSVersion(ExtensionVersion)
    case invalidIdentifier(field: String, value: String)
    case matchingBundleIdentifiers
    case extensionIsNotContainedByProvider
    case invalidProtocolVersionRange
    case noArchitectures
    case noEntryPoints
    case duplicateMetadataEntryPoint(String)
    case duplicatePackageEntryPoint(String)
    case entryPointMismatch(String)
    case missingRemoteScene(String)
    case unexpectedDeclarativeScene(String)
    case duplicatePermission(ExtensionDeclaredPermission.Kind)
    case emptyPermissionUsageDescriptionKey(ExtensionDeclaredPermission.Kind)
    case hostActionRequiresOpenDestination(ExtensionHostAction)
    case incompleteSneakPeekActions

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchemaVersion(version):
            "Unsupported extension package schema version: \(version)"
        case .artifactKindMismatch:
            "Package and metadata artifact kinds do not match"
        case let .invalidSource(source):
            "Unsupported package extension source: \(source.rawValue)"
        case .missingAppExtensionMetadata:
            "App-extension metadata is required"
        case .unexpectedAppExtensionMetadata:
            "App-extension metadata is only valid for app-extension artifacts"
        case let .unsupportedMinimumMacOSVersion(version):
            "App extensions require macOS 26 or newer; manifest declared \(version)"
        case let .invalidIdentifier(field, value):
            "Invalid \(field): \(value)"
        case .matchingBundleIdentifiers:
            "Provider and extension bundle identifiers must be different"
        case .extensionIsNotContainedByProvider:
            "The extension bundle identifier must be prefixed by its provider bundle identifier"
        case .invalidProtocolVersionRange:
            "Protocol versions must be positive and ordered"
        case .noArchitectures:
            "The app-extension artifact must declare at least one architecture"
        case .noEntryPoints:
            "The package must declare at least one entry point"
        case let .duplicateMetadataEntryPoint(id):
            "Metadata entry point identifier is duplicated: \(id)"
        case let .duplicatePackageEntryPoint(id):
            "Package entry point identifier is duplicated: \(id)"
        case let .entryPointMismatch(id):
            "Package and metadata entry points do not correspond: \(id)"
        case let .missingRemoteScene(id):
            "Remote-scene entry point has no scene name: \(id)"
        case let .unexpectedDeclarativeScene(id):
            "Declarative entry point must not have a scene name: \(id)"
        case let .duplicatePermission(kind):
            "Permission is declared more than once: \(kind.rawValue)"
        case let .emptyPermissionUsageDescriptionKey(kind):
            "Permission has an empty usage-description key: \(kind.rawValue)"
        case let .hostActionRequiresOpenDestination(action):
            "Host action requires an open-destination entry point: \(action.rawValue)"
        case .incompleteSneakPeekActions:
            "Show and hide sneak-peek actions must be declared together"
        }
    }
}

/// Selects the package origin permitted by an installation policy. A manifest's
/// source is a declaration; callers must still verify the source-specific trust
/// evidence before installing executable code.
public enum ExtensionPackageValidationContext: Equatable, Sendable {
    case localDeveloper
    case marketplace

    var expectedSource: ExtensionSource {
        switch self {
        case .localDeveloper: .localDeveloper
        case .marketplace: .marketplace
        }
    }
}

/// Pure validation for package metadata. It performs no discovery, file I/O,
/// framework loading, or wire-target lookup.
public enum ExtensionPackageManifestValidator {
    /// Validates a user-selected local-developer package for backwards
    /// compatibility with the Phase 2 installer.
    public static func validate(_ manifest: ExtensionPackageManifest) throws {
        try validate(manifest, context: .localDeveloper)
    }

    /// Validates the common package contract plus the expected distribution
    /// declaration. This does not establish marketplace approval or signing
    /// policy; those checks belong to the installation trust policy.
    public static func validate(
        _ manifest: ExtensionPackageManifest,
        context: ExtensionPackageValidationContext
    ) throws {
        guard manifest.schemaVersion == ExtensionPackageManifest.currentSchemaVersion else {
            throw ExtensionPackageManifestValidationError.unsupportedSchemaVersion(manifest.schemaVersion)
        }
        guard manifest.metadata.artifactKind == manifest.artifact.kind else {
            throw ExtensionPackageManifestValidationError.artifactKindMismatch
        }
        guard manifest.metadata.source == context.expectedSource else {
            throw ExtensionPackageManifestValidationError.invalidSource(manifest.metadata.source)
        }

        switch manifest.artifact.kind {
        case .appExtension:
            guard let appExtension = manifest.artifact.appExtension else {
                throw ExtensionPackageManifestValidationError.missingAppExtensionMetadata
            }
            try validate(appExtension)
        case .compiledIn, .xpcService:
            guard manifest.artifact.appExtension == nil else {
                throw ExtensionPackageManifestValidationError.unexpectedAppExtensionMetadata
            }
        }

        try validateEntryPoints(manifest)
        try validatePermissions(manifest.permissions)
        try validateHostActions(manifest)
    }

    private static func validate(_ artifact: AppExtensionArtifactMetadata) throws {
        let minimum = ExtensionVersion(major: 26, minor: 0, patch: 0)
        guard artifact.minimumMacOSVersion >= minimum else {
            throw ExtensionPackageManifestValidationError.unsupportedMinimumMacOSVersion(
                artifact.minimumMacOSVersion
            )
        }
        try validateIdentifier(artifact.providerBundleIdentifier, field: "provider bundle identifier")
        try validateIdentifier(artifact.extensionBundleIdentifier, field: "extension bundle identifier")
        try validateIdentifier(artifact.extensionPointIdentifier, field: "extension-point identifier")
        guard artifact.providerBundleIdentifier != artifact.extensionBundleIdentifier else {
            throw ExtensionPackageManifestValidationError.matchingBundleIdentifiers
        }
        guard artifact.extensionBundleIdentifier.hasPrefix(artifact.providerBundleIdentifier + ".") else {
            throw ExtensionPackageManifestValidationError.extensionIsNotContainedByProvider
        }
        guard artifact.protocolVersions.minimum > 0,
              artifact.protocolVersions.maximum >= artifact.protocolVersions.minimum
        else {
            throw ExtensionPackageManifestValidationError.invalidProtocolVersionRange
        }
        guard !artifact.architectures.isEmpty else {
            throw ExtensionPackageManifestValidationError.noArchitectures
        }
    }

    private static func validateEntryPoints(_ manifest: ExtensionPackageManifest) throws {
        guard !manifest.entryPoints.isEmpty else {
            throw ExtensionPackageManifestValidationError.noEntryPoints
        }

        var metadataByID: [String: ExtensionEntryPoint] = [:]
        for entryPoint in manifest.metadata.entryPoints {
            guard metadataByID.updateValue(entryPoint, forKey: entryPoint.id) == nil else {
                throw ExtensionPackageManifestValidationError.duplicateMetadataEntryPoint(entryPoint.id)
            }
        }

        var packageIDs = Set<String>()
        for descriptor in manifest.entryPoints {
            guard packageIDs.insert(descriptor.id).inserted else {
                throw ExtensionPackageManifestValidationError.duplicatePackageEntryPoint(descriptor.id)
            }
            guard let metadataEntryPoint = metadataByID[descriptor.id],
                  metadataEntryPoint.kind == descriptor.entryPoint.kind
            else {
                throw ExtensionPackageManifestValidationError.entryPointMismatch(descriptor.id)
            }
            switch descriptor.presentationMode {
            case .remoteScene:
                guard hasValue(descriptor.sceneName) else {
                    throw ExtensionPackageManifestValidationError.missingRemoteScene(descriptor.id)
                }
            case .declarative:
                guard descriptor.sceneName == nil else {
                    throw ExtensionPackageManifestValidationError.unexpectedDeclarativeScene(descriptor.id)
                }
            }
        }

        guard packageIDs.count == metadataByID.count else {
            let missing = metadataByID.keys.first(where: { !packageIDs.contains($0) }) ?? "unknown"
            throw ExtensionPackageManifestValidationError.entryPointMismatch(missing)
        }
    }

    private static func validatePermissions(_ permissions: Set<ExtensionDeclaredPermission>) throws {
        var kinds = Set<ExtensionDeclaredPermission.Kind>()
        for permission in permissions {
            guard kinds.insert(permission.kind).inserted else {
                throw ExtensionPackageManifestValidationError.duplicatePermission(permission.kind)
            }
            guard hasValue(permission.usageDescriptionKey) else {
                throw ExtensionPackageManifestValidationError.emptyPermissionUsageDescriptionKey(permission.kind)
            }
        }
    }

    private static func validateHostActions(_ manifest: ExtensionPackageManifest) throws {
        let hasOpenDestination = manifest.metadata.entryPoints.contains { $0.kind == .openDestination }
        for action in [ExtensionHostAction.openDestination, .closeNotch]
            where manifest.hostActions.contains(action) && !hasOpenDestination {
            throw ExtensionPackageManifestValidationError.hostActionRequiresOpenDestination(action)
        }
        guard manifest.hostActions.contains(.showSneakPeek)
                == manifest.hostActions.contains(.hideSneakPeek) else {
            throw ExtensionPackageManifestValidationError.incompleteSneakPeekActions
        }
    }

    private static func validateIdentifier(_ value: String, field: String) throws {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        let valid = components.count >= 2 && components.allSatisfy { component in
            guard let first = component.first, let last = component.last,
                  first != "-", last != "-" else { return false }
            return component.allSatisfy { character in
                character.isASCII && (character.isLetter || character.isNumber || character == "-")
            }
        }
        guard valid else {
            throw ExtensionPackageManifestValidationError.invalidIdentifier(field: field, value: value)
        }
    }

    private static func hasValue(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
