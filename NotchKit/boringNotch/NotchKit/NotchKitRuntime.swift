//
//  NotchKitRuntime.swift
//  NotchKit
//
//  Composition root for the NotchKit extension runtime.
//

import Foundation
import NotchAPI
import NotchExtensions
import os

/// Shared composition of the registry, manager, catalog, and router.
///
/// The app host creates this once at launch. It owns no rendering; it is the
/// seam through which open destinations are registered and selected.
@MainActor
final class NotchKitRuntime {
    static let shared = NotchKitRuntime()

    let registry = ExtensionRegistry()
    let catalog = ExtensionCatalog()
    let manager: ExtensionManager
    let router: NotchRouter

    private let logger = Logger(subsystem: "com.boringnotch", category: "NotchKit")

    private init() {
        let store = UserDefaultsExtensionStateStore()
        manager = ExtensionManager(registry: registry, store: store)
        router = NotchRouter(
            registry: registry,
            manager: manager,
            homeID: BuiltInExtensionIDs.homeDestination
        )
    }

    /// Registers the first-party catalog and reconciles persisted state.
    func bootstrap() {
        do {
            try catalog.add(contentsOf: BuiltInExtensions.descriptors())
            try catalog.registerAll(into: registry)
            manager.reconcile()
            router.refreshAvailability()
        } catch {
            logger.error("NotchKit bootstrap failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Re-evaluates enabled state after a settings change.
    func refresh() {
        manager.reconcile()
        router.refreshAvailability()
    }
}