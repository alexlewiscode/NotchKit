//
//  ExtensionContext.swift
//  NotchExtensionSDK
//
//  The host services and teardown scope handed to an activated extension.
//

import Foundation

/// Everything an activated extension is allowed to use.
///
/// The context is created by the host, is valid only for the lifetime of one
/// activation, and is discarded on deactivation.
@MainActor
public final class ExtensionContext {
    /// The identity of the owning extension.
    public let identity: ExtensionIdentity
    /// Teardown scope for everything the extension starts.
    public let cancellation: ExtensionCancellationBag
    /// Display-targeted presentation requests.
    public let presentation: any NotchPresentationService
    /// Namespaced persistence scoped to this extension.
    public let store: any ExtensionScopedStore
    /// Permission queries and requests.
    public let permissions: any NotchPermissionService

    public init(
        identity: ExtensionIdentity,
        cancellation: ExtensionCancellationBag,
        presentation: any NotchPresentationService,
        store: any ExtensionScopedStore,
        permissions: any NotchPermissionService
    ) {
        self.identity = identity
        self.cancellation = cancellation
        self.presentation = presentation
        self.store = store
        self.permissions = permissions
    }
}
