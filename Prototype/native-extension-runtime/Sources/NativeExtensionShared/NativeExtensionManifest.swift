import Foundation

public struct NativeExtensionManifest: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let id: String
    public let displayName: String
    public let summary: String
    public let extensionVersion: String
    public let minimumHostVersion: String
    public let minimumMacOSVersion: String
    public let artifactKind: ArtifactKind
    public let providerBundleIdentifier: String
    public let extensionBundleIdentifier: String
    public let entryPoints: [EntryPoint]

    public enum ArtifactKind: String, Codable, Sendable {
        case appExtension = "app-extension"
    }

    public struct EntryPoint: Codable, Equatable, Sendable {
        public let id: String
        public let kind: Kind
        public let sceneName: String

        public enum Kind: String, Codable, Sendable {
            case openDestination = "open-destination"
            case closedNotchContribution = "closed-notch-contribution"
            case settingsDestination = "settings-destination"
        }

        public init(id: String, kind: Kind, sceneName: String) {
            self.id = id
            self.kind = kind
            self.sceneName = sceneName
        }
    }

    public init(
        schemaVersion: Int,
        id: String,
        displayName: String,
        summary: String,
        extensionVersion: String,
        minimumHostVersion: String,
        minimumMacOSVersion: String,
        artifactKind: ArtifactKind,
        providerBundleIdentifier: String,
        extensionBundleIdentifier: String,
        entryPoints: [EntryPoint]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.displayName = displayName
        self.summary = summary
        self.extensionVersion = extensionVersion
        self.minimumHostVersion = minimumHostVersion
        self.minimumMacOSVersion = minimumMacOSVersion
        self.artifactKind = artifactKind
        self.providerBundleIdentifier = providerBundleIdentifier
        self.extensionBundleIdentifier = extensionBundleIdentifier
        self.entryPoints = entryPoints
    }
}

public enum NativeExtensionManifestError: Error, Equatable, LocalizedError {
    case unsupportedSchemaVersion(Int)
    case invalidIdentifier(field: String, value: String)
    case invalidVersion(field: String, value: String)
    case unsupportedMinimumMacOSVersion(String)
    case matchingBundleIdentifiers
    case extensionIsNotContainedByProvider
    case noEntryPoints
    case duplicateEntryPoint(String)
    case missingSceneName(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchemaVersion(version):
            "Unsupported manifest schema version: \(version)"
        case let .invalidIdentifier(field, value):
            "Invalid \(field): \(value)"
        case let .invalidVersion(field, value):
            "Invalid \(field): \(value)"
        case let .unsupportedMinimumMacOSVersion(version):
            "Native extensions require macOS 26 or newer; manifest declared \(version)"
        case .matchingBundleIdentifiers:
            "The provider and extension must have distinct bundle identifiers"
        case .extensionIsNotContainedByProvider:
            "The extension bundle identifier must be prefixed by its provider bundle identifier"
        case .noEntryPoints:
            "The manifest must declare at least one entry point"
        case let .duplicateEntryPoint(id):
            "Duplicate entry point identifier: \(id)"
        case let .missingSceneName(id):
            "Entry point \(id) has no remote scene name"
        }
    }
}

public enum NativeExtensionManifestValidator {
    public static func validate(_ manifest: NativeExtensionManifest) throws {
        guard manifest.schemaVersion == NativeExtensionManifest.currentSchemaVersion else {
            throw NativeExtensionManifestError.unsupportedSchemaVersion(manifest.schemaVersion)
        }

        try validateIdentifier(manifest.id, field: "extension id")
        try validateIdentifier(manifest.providerBundleIdentifier, field: "provider bundle identifier")
        try validateIdentifier(manifest.extensionBundleIdentifier, field: "extension bundle identifier")
        try validateVersion(manifest.extensionVersion, field: "extension version")
        try validateVersion(manifest.minimumHostVersion, field: "minimum host version")
        try validateVersion(manifest.minimumMacOSVersion, field: "minimum macOS version")

        guard majorVersion(manifest.minimumMacOSVersion) >= 26 else {
            throw NativeExtensionManifestError.unsupportedMinimumMacOSVersion(
                manifest.minimumMacOSVersion
            )
        }
        guard manifest.providerBundleIdentifier != manifest.extensionBundleIdentifier else {
            throw NativeExtensionManifestError.matchingBundleIdentifiers
        }
        guard manifest.extensionBundleIdentifier.hasPrefix(manifest.providerBundleIdentifier + ".") else {
            throw NativeExtensionManifestError.extensionIsNotContainedByProvider
        }
        guard !manifest.entryPoints.isEmpty else {
            throw NativeExtensionManifestError.noEntryPoints
        }

        var entryPointIDs = Set<String>()
        for entryPoint in manifest.entryPoints {
            try validateIdentifier(entryPoint.id, field: "entry point id")
            guard entryPointIDs.insert(entryPoint.id).inserted else {
                throw NativeExtensionManifestError.duplicateEntryPoint(entryPoint.id)
            }
            guard !entryPoint.sceneName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw NativeExtensionManifestError.missingSceneName(entryPoint.id)
            }
        }
    }

    private static func validateIdentifier(_ value: String, field: String) throws {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        let isValid = components.count >= 3 && components.allSatisfy { component in
            guard let first = component.first, let last = component.last,
                  first != "-", last != "-"
            else { return false }
            return component.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
        guard isValid else {
            throw NativeExtensionManifestError.invalidIdentifier(field: field, value: value)
        }
    }

    private static func validateVersion(_ value: String, field: String) throws {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) })
        else {
            throw NativeExtensionManifestError.invalidVersion(field: field, value: value)
        }
    }

    private static func majorVersion(_ value: String) -> Int {
        Int(value.split(separator: ".", maxSplits: 1)[0]) ?? 0
    }
}
