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
    /// Lifecycle-independent settings pages for the Extensions hub.
    ///
    /// Evaluated by the host when building its settings catalog, and again when
    /// the hub renders a detail. It must not create or capture a live
    /// `NotchExtension`, an `ExtensionContext`, or a long-lived service; the
    /// returned destinations may only read configuration and build views on
    /// demand. Defaults to no destinations, so declaring settings is optional.
    public let settings: @MainActor () -> [ExtensionSettingsDestination]
    /// Creates the instance when the extension is activated.
    public let makeInstance: @MainActor (ExtensionContext) -> any NotchExtension

    public init(
        metadata: ExtensionMetadata,
        settings: @escaping @MainActor () -> [ExtensionSettingsDestination] = { [] },
        makeInstance: @escaping @MainActor (ExtensionContext) -> any NotchExtension
    ) {
        self.metadata = metadata
        self.settings = settings
        self.makeInstance = makeInstance
    }

    public var id: ExtensionIdentity { metadata.id }
}
