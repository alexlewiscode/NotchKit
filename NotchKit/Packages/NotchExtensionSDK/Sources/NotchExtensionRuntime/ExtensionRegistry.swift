//
//  ExtensionRegistry.swift
//  NotchExtensionRuntime
//
//  Validates and stores extension definitions (metadata + factory).
//

import Foundation
import NotchExtensionSDK

/// Errors raised while registering definitions.
public enum ExtensionRegistryError: Error, Equatable {
    case duplicateExtensionID(ExtensionIdentity)
    case incompatibleManifest(ExtensionCompatibilityError)
}

/// Validates and provides registered extension definitions.
///
/// Registration validates the manifest against the running host and SDK and
/// rejects duplicate identities. Registration never creates a runtime instance.
public final class ExtensionRegistry {
    private var definitionsByID: [ExtensionIdentity: ExtensionDefinition] = [:]
    private let hostVersion: ExtensionVersion
    private let sdkVersion: ExtensionAPIVersion

    public init(hostVersion: ExtensionVersion, sdkVersion: ExtensionAPIVersion = .current) {
        self.hostVersion = hostVersion
        self.sdkVersion = sdkVersion
    }

    /// Registers a definition after validating its manifest.
    public func register(_ definition: ExtensionDefinition) throws {
        guard definitionsByID[definition.id] == nil else {
            throw ExtensionRegistryError.duplicateExtensionID(definition.id)
        }
        do {
            try ExtensionCompatibility.validate(
                definition.metadata, hostVersion: hostVersion, sdkVersion: sdkVersion
            )
        } catch let error as ExtensionCompatibilityError {
            throw ExtensionRegistryError.incompatibleManifest(error)
        }
        definitionsByID[definition.id] = definition
    }

    /// Removes a definition. Returns the removed definition, if any.
    @discardableResult
    public func remove(_ id: ExtensionIdentity) -> ExtensionDefinition? {
        definitionsByID.removeValue(forKey: id)
    }

    /// All registered definitions, sorted by identity.
    public var definitions: [ExtensionDefinition] {
        definitionsByID.values.sorted { $0.id < $1.id }
    }

    /// Metadata for all registered definitions, sorted by identity.
    public var metadata: [ExtensionMetadata] {
        definitions.map(\.metadata)
    }

    public func definition(for id: ExtensionIdentity) -> ExtensionDefinition? {
        definitionsByID[id]
    }

    public func metadata(for id: ExtensionIdentity) -> ExtensionMetadata? {
        definitionsByID[id]?.metadata
    }
}