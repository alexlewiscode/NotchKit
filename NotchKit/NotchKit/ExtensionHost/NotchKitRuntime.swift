//
//  NotchKitRuntime.swift
//  NotchKit
//
//  Composition root for the NotchKit extension runtime.
//

import Foundation
import NotchExtensionSDK
import NotchExtensionRuntime
import os

/// Small holder so the context factory can read the active display without
/// capturing the runtime during its own initialization.
@MainActor
final class ActiveDisplayBox {
    var value = DisplayID("display.primary")
}

/// Shared composition of the registry, manager, contributions, presentation
/// coordinator, and lifecycle host.
///
/// Extension instances and host services are app-wide; routing and presentation
/// are per-display through `presentation`.
@MainActor
final class NotchKitRuntime {
    static let shared = NotchKitRuntime()

    let registry: ExtensionRegistry
    let catalog = ExtensionCatalog()
    let manager: ExtensionManager
    let contributions = ContributionStore()
    let presentation: PresentationCoordinator
    let host: ExtensionHost

    private let displayBox = ActiveDisplayBox()
    private let logger = Logger(subsystem: NotchKitIdentity.bundleIdentifier, category: "NotchKit")

    var activeDisplayID: DisplayID { displayBox.value }

    private init() {
        registry = ExtensionRegistry(hostVersion: Self.hostVersion())
        manager = ExtensionManager(registry: registry, store: UserDefaultsExtensionStateStore())
        presentation = PresentationCoordinator(
            contributions: contributions,
            manager: manager,
            homeID: BuiltInExtensionIDs.homeDestination
        )
        let displayBox = self.displayBox
        let presentation = self.presentation
        host = ExtensionHost(
            registry: registry,
            manager: manager,
            contributions: contributions
        ) { id, bag in
            ExtensionContext(
                identity: id,
                cancellation: bag,
                presentation: HostPresentationService(coordinator: presentation) {
                    displayBox.value
                },
                store: UserDefaultsExtensionScopedStore(identity: id),
                permissions: HostPermissionService()
            )
        }
    }

    /// Registers the first-party catalog and starts enabled extensions.
    func bootstrap() {
        do {
            try catalog.add(contentsOf: BuiltInExtensions.definitions())
            try catalog.registerAll(into: registry)
            host.start()
            presentation.refreshAll()
        } catch {
            logger.error("NotchKit bootstrap failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Re-evaluates enabled state and routing after a settings change.
    func refresh() {
        manager.reconcile()
        host.reconcileNow()
        presentation.refreshAll()
    }

    func setActiveDisplay(_ id: DisplayID) {
        displayBox.value = id
    }

    func displayID(for screenUUID: String?) -> DisplayID {
        guard let screenUUID, !screenUUID.isEmpty else { return DisplayID("display.primary") }
        return DisplayID(screenUUID)
    }

    func router(for display: DisplayID) -> NotchRouter {
        presentation.router(for: display)
    }

    func select(_ destination: DestinationID, on display: DisplayID) {
        router(for: display).select(destination)
    }

    func selectOnActiveDisplay(_ destination: DestinationID) {
        select(destination, on: activeDisplayID)
    }

    private static func hostVersion() -> ExtensionVersion {
        let raw = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return raw.flatMap(ExtensionVersion.init) ?? ExtensionVersion(major: 1, minor: 0, patch: 0)
    }
}
