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

#if !NOTCHKIT_CORE_ONLY
import BatteryExtension
#endif

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
    /// Authoritative settings catalog for the Extensions hub.
    let settingsCatalog = SettingsCatalog()
    let manager: ExtensionManager
    let contributions = ContributionStore()
    let presentation: PresentationCoordinator
    let host: ExtensionHost

    #if !NOTCHKIT_CORE_ONLY
    /// The app-wide battery service shared by the Battery extension and the
    /// open-notch header indicator. Created once, never per display.
    let batteryMonitor = BatteryMonitor()
    #endif

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
                presentation: HostPresentationService(
                    coordinator: presentation,
                    viewCoordinator: BoringViewCoordinator.shared
                ) {
                    displayBox.value
                },
                store: UserDefaultsExtensionScopedStore(identity: id),
                permissions: HostPermissionService()
            )
        }
        // Async activation/deactivation completes after `bootstrap`, so refresh
        // presentation whenever a phase changes.
        host.onStateChanged = { [weak presentation] in
            presentation?.refreshAll()
        }
        // When accessibility is granted while a permission-gated feature is
        // blocked, retry it automatically. This is the host-side counterpart to
        // the row's explicit "Grant Access" action.
        accessibilityObserver = NotificationCenter.default.addObserver(
            forName: .accessibilityAuthorizationChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.retryPermissionBlockedFeatures()
            }
        }
    }

    private var accessibilityObserver: NSObjectProtocol?

    private func retryPermissionBlockedFeatures() {
        for identity in BuiltInExtensionIDs.toggleableFeatures
        where manager.isEnabled(identity) {
            if case .requiresPermission = host.phase(for: identity) {
                host.retry(identity)
            }
        }
    }

    /// Registers the first-party catalog and starts enabled extensions.
    func bootstrap() {
        do {
            var definitions = BuiltInExtensions.definitions()
            definitions.append(contentsOf: LegacyFeatureSettings.definitions())
            #if !NOTCHKIT_CORE_ONLY
            definitions.append(try BatteryExtensionFactory.definition(monitor: batteryMonitor))
            #endif
            try catalog.add(contentsOf: definitions)
            try catalog.registerAll(into: registry)
            rebuildSettingsCatalog()
            // Seed authoritative enablement from legacy masters once, before the
            // host reconciles and activates anything.
            FeatureEnablementMigration.runIfNeeded(manager: manager)
            host.start()
            presentation.refreshAll()
        } catch {
            logger.error("NotchKit bootstrap failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Rebuilds the authoritative settings catalog from the registry.
    ///
    /// Called after definitions are registered and after any definition is
    /// removed, so a removed feature leaves no stale catalog entry or route.
    func rebuildSettingsCatalog() {
        var runtimeManaged: Set<FeatureSettingsID> = [
            FeatureSettingsID(BuiltInExtensionIDs.shelf.rawValue),
            LegacyFeatureSettings.calendarFeatureID,
            LegacyFeatureSettings.mediaFeatureID,
            LegacyFeatureSettings.hudFeatureID,
            LegacyFeatureSettings.cameraFeatureID,
        ]
        var order: [FeatureSettingsID: Int] = [
            FeatureSettingsID(BuiltInExtensionIDs.shelf.rawValue): 20,
            LegacyFeatureSettings.calendarFeatureID: LegacyFeatureSettings.calendarOrder,
            LegacyFeatureSettings.mediaFeatureID: LegacyFeatureSettings.mediaOrder,
            LegacyFeatureSettings.hudFeatureID: LegacyFeatureSettings.hudOrder,
            LegacyFeatureSettings.cameraFeatureID: LegacyFeatureSettings.cameraOrder,
        ]
        #if !NOTCHKIT_CORE_ONLY
        let batteryFeatureID = FeatureSettingsID(BatteryIds.identity.rawValue)
        runtimeManaged.insert(batteryFeatureID)
        order[batteryFeatureID] = 0
        #endif
        settingsCatalog.rebuild(
            from: registry.definitions,
            runtimeManaged: runtimeManaged,
            order: order,
            adapters: []
        )
    }

    /// Whether a feature's authoritative master enabled state is on.
    ///
    /// Core renderers use this instead of reading per-feature legacy
    /// preferences, so a disabled feature hides its UI consistently.
    func isFeatureEnabled(_ id: ExtensionIdentity) -> Bool {
        manager.isEnabled(id)
    }

    /// The runtime phase for a feature, if it has been reconciled.
    func phase(for id: ExtensionIdentity) -> ExtensionRuntimePhase {
        host.phase(for: id)
    }

    /// Removes an extension and prunes the settings catalog. There is no
    /// production uninstall surface today; this keeps the removal path honest
    /// for tests and future code.
    func removeExtension(_ id: ExtensionIdentity) {
        host.remove(id)
        rebuildSettingsCatalog()
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
