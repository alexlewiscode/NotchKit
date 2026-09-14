//
//  ExtensionCatalog.swift
//  NotchExtensions
//
//  The first-party catalog/registration boundary.
//

import Foundation
import NotchAPI

/// The first-party catalog of extensions.
///
/// The app host builds descriptors (which reference app views) and adds them to
/// the catalog. The catalog validates ids at add time and registers everything
/// into an `ExtensionRegistry` at startup. Phase 1 does not move all features
/// here; it establishes the boundary.
public final class ExtensionCatalog {
    private var descriptorsByID: [ExtensionIdentity: ExtensionDescriptor] = [:]

    public init() {}

    /// Adds a descriptor to the catalog, rejecting duplicate identities.
    public func add(_ descriptor: ExtensionDescriptor) throws {
        guard descriptorsByID[descriptor.id] == nil else {
            throw ExtensionRegistryError.duplicateExtensionID(descriptor.id)
        }
        descriptorsByID[descriptor.id] = descriptor
    }

    /// Adds several descriptors.
    public func add(contentsOf descriptors: [ExtensionDescriptor]) throws {
        for descriptor in descriptors {
            try add(descriptor)
        }
    }

    /// The catalogued descriptors, sorted by identity.
    public var descriptors: [ExtensionDescriptor] {
        descriptorsByID.values.sorted { $0.id < $1.id }
    }

    /// Registers every catalogued descriptor into the supplied registry.
    public func registerAll(into registry: ExtensionRegistry) throws {
        for descriptor in descriptors {
            try registry.register(descriptor)
        }
    }
}
