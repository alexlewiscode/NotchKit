//
//  BatteryExtension.swift
//  BatteryExtension
//
//  The activated Battery instance and its host definition factory.
//

import Foundation
import NotchExtensionSDK
import SwiftUI

/// The activated Battery extension.
///
/// Owns exactly one `BatteryMonitor`. `activate()` starts it and registers
/// teardown; `deactivate()` stops it and cancels everything. The monitor is
/// app-wide, so multiple displays observing the same instance never start a
/// second observer.
@MainActor
public final class BatteryExtension: NotchExtension {
    private let context: ExtensionContext
    private let monitor: BatteryMonitor
    private var isActive = false
    /// Test seam: forces `activate()` to throw after the service has started,
    /// so partial-failure teardown can be exercised.
    var activationFailure: Error?

    public init(context: ExtensionContext, monitor: BatteryMonitor) {
        self.context = context
        self.monitor = monitor
    }

    public func activate() async throws {
        isActive = true
        // Deactivation must stop the service even if it was started here.
        context.cancellation.add { [weak monitor] in
            monitor?.stop()
        }
        monitor.onChange = { [weak self] snapshot in
            self?.snapshotChanged(snapshot)
        }
        monitor.start()
        if let activationFailure {
            throw activationFailure
        }
    }

    public func deactivate() {
        isActive = false
        monitor.onChange = nil
        monitor.stop()
        context.cancellation.cancelAll()
    }

    public func closedNotchContributions() -> [ClosedNotchContribution] {
        guard isActive else { return [] }
        return [
            ClosedNotchContribution(
                id: BatteryIds.contribution,
                extensionID: BatteryIds.identity,
                region: .exclusion,
                priority: 400,
                tieBreaker: "battery",
                isAvailable: { snapshot in
                    !snapshot.isNotchOpen
                        && snapshot.isExpandingViewShown
                        && snapshot.expandingViewKind == "battery"
                        && BatterySettings.showPowerStatusNotifications
                },
                makeView: { [monitor] in AnyView(BatteryNotificationView(monitor: monitor)) },
                preferredChinWidth: { _ in 640 }
            )
        ]
    }

    /// Requests the core-owned expanding notification. Core decides whether and
    /// how to present it; the extension only asks.
    private func snapshotChanged(_ snapshot: BatterySnapshot) {
        guard BatterySettings.showPowerStatusNotifications else { return }
        context.presentation.request(
            .showSneakPeek(
                kind: "battery",
                value: Double(snapshot.currentCapacity),
                duration: 3
            ),
            target: .active
        )
    }
}

/// Builds the Battery `ExtensionDefinition`.
///
/// The host injects the app-wide monitor so the header indicator and the
/// extension instance observe the same service. The settings page is declared
/// lifecycle-independently here, so it is reachable while Battery is disabled or
/// failed and opening it never starts the monitor.
public enum BatteryExtensionFactory {
    /// The runtime-free manifest. Safe to read without starting services.
    public static func metadata() throws -> ExtensionMetadata {
        try BatteryManifest.metadata()
    }

    /// A definition whose instance shares `monitor`.
    @MainActor
    public static func definition(monitor: BatteryMonitor) throws -> ExtensionDefinition {
        ExtensionDefinition(
            metadata: try BatteryManifest.metadata(),
            settings: {
                [
                    ExtensionSettingsDestination(
                        id: BatteryIds.settingsDestination,
                        title: "Battery",
                        iconSystemName: "battery.100",
                        isAvailable: { true },
                        makeView: { AnyView(BatterySettingsView()) }
                    )
                ]
            }
        ) { context in
            BatteryExtension(context: context, monitor: monitor)
        }
    }
}