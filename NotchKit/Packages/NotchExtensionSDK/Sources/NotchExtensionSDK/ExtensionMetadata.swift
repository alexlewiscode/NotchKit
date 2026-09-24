//
//  ExtensionMetadata.swift
//  NotchExtensionSDK
//
//  Metadata-only manifest. Carries no runtime object and never instantiates a
//  feature service: listing extensions reads only this value.
//

import Foundation

/// The origin of an extension.
public enum ExtensionSource: String, Hashable, Codable, Sendable {
    /// An extension compiled into the app.
    case firstParty
    /// An unpackaged extension installed directly by a local developer.
    case localDeveloper
    /// A separately distributed package approved by the NotchKit Hub. The
    /// declaration alone is not proof of Hub approval; installation requires a
    /// separately verified Hub release receipt.
    case marketplace
}

/// The complete, runtime-free description of an extension.
///
/// `ExtensionMetadata` is the canonical manifest contract. It is `Codable`, so
/// the same shape is used for the on-disk JSON manifest and the in-process
/// registration value. It never contains closures, views, or services.
public struct ExtensionMetadata: Identifiable, Codable, Hashable, Sendable {
    /// Stable reverse-DNS identity.
    public let id: ExtensionIdentity
    /// User-visible name.
    public let displayName: String
    /// Optional short description.
    public let summary: String?
    /// SF Symbol used to represent the extension.
    public let iconSystemName: String
    /// The extension's own semantic version.
    public let extensionVersion: ExtensionVersion
    /// The extension SDK/API version the extension was built against.
    public let apiVersion: ExtensionAPIVersion
    /// Host application versions this extension supports.
    public let supportedHostVersions: ExtensionVersionRange
    /// SDK versions this extension supports.
    public let supportedSDKVersions: ExtensionVersionRange
    /// Declared contribution capabilities.
    public let capabilities: Set<ExtensionCapability>
    /// How the artifact is delivered and executed.
    public let artifactKind: ExtensionArtifactKind
    /// Declared attachment points.
    public let entryPoints: [ExtensionEntryPoint]
    /// Whether the extension is enabled on first run.
    public let defaultEnabled: Bool
    /// The origin of the extension.
    public let source: ExtensionSource

    public init(
        id: ExtensionIdentity,
        displayName: String,
        summary: String? = nil,
        iconSystemName: String,
        extensionVersion: ExtensionVersion,
        apiVersion: ExtensionAPIVersion = .current,
        supportedHostVersions: ExtensionVersionRange,
        supportedSDKVersions: ExtensionVersionRange,
        capabilities: Set<ExtensionCapability>,
        artifactKind: ExtensionArtifactKind = .compiledIn,
        entryPoints: [ExtensionEntryPoint],
        defaultEnabled: Bool,
        source: ExtensionSource = .firstParty
    ) {
        self.id = id
        self.displayName = displayName
        self.summary = summary
        self.iconSystemName = iconSystemName
        self.extensionVersion = extensionVersion
        self.apiVersion = apiVersion
        self.supportedHostVersions = supportedHostVersions
        self.supportedSDKVersions = supportedSDKVersions
        self.capabilities = capabilities
        self.artifactKind = artifactKind
        self.entryPoints = entryPoints
        self.defaultEnabled = defaultEnabled
        self.source = source
    }

    /// Entry points of a given kind, in declaration order.
    public func entryPoints(of kind: ExtensionEntryPointKind) -> [ExtensionEntryPoint] {
        entryPoints.filter { $0.kind == kind }
    }
}
