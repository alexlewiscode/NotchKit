//
//  ExtensionCatalog.swift
//  NotchExtensionRuntime
//
//  The first-party catalog/registration boundary.
//

import Foundation
import NotchExtensionSDK

/// The catalog of extension definitions known to the host.
///
/// The app host builds definitions (metadata plus a factory) and adds them to
/// the catalog. The catalog validates ids at add time and registers everything
/// into an `ExtensionRegistry` at startup. Adding a definition never creates a
/// runtime instance.
public final class ExtensionCatalog {
    private var definitionsByID: [ExtensionIdentity: ExtensionDefinition] = [:]

    public init() {}

    /// Adds a definition, rejecting duplicate identities.
    public func add(_ definition: ExtensionDefinition) throws {
        guard definitionsByID[definition.id] == nil else {
            throw ExtensionRegistryError.duplicateExtensionID(definition.id)
        }
        definitionsByID[definition.id] = definition
    }

    /// Adds several definitions.
    public func add(contentsOf definitions: [ExtensionDefinition]) throws {
        for definition in definitions {
            try add(definition)
        }
    }

    /// The catalogued definitions, sorted by identity.
    public var definitions: [ExtensionDefinition] {
        definitionsByID.values.sorted { $0.id < $1.id }
    }

    /// Registers a catalogued definition into the supplied registry.
    public func registerAll(into registry: ExtensionRegistry) throws {
        for definition in definitions {
            try registry.register(definition)
        }
    }
}