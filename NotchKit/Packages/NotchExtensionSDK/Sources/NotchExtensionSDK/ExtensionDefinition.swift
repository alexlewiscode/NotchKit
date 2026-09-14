//
//  ExtensionDefinition.swift
//  NotchExtensionSDK
//
//  Metadata plus the factory that creates a runtime instance on demand.
//

import Foundation

/// A registered extension: runtime-free metadata and a factory.
///
/// Holding a definition does not create services. The factory is called only
/// when the extension is enabled. For `.compiledIn` extensions the factory
/// closes over trusted, statically linked Swift code.
public struct ExtensionDefinition {
    /// Runtime-free manifest.
    public let metadata: ExtensionMetadata
    /// Creates the instance when the extension is activated.
    public let makeInstance: @MainActor (ExtensionContext) -> any NotchExtension

    public init(
        metadata: ExtensionMetadata,
        makeInstance: @escaping @MainActor (ExtensionContext) -> any NotchExtension
    ) {
        self.metadata = metadata
        self.makeInstance = makeInstance
    }

    public var id: ExtensionIdentity { metadata.id }
}
