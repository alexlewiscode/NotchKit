//
//  PermissionRefreshCoordinatorTests.swift
//  NotchKitTests
//
//  The targeted, idempotent reconciliation used by "Refresh Status" and app
//  reactivation. Pure closure-level coverage so no host or TCC is involved.
//

import NotchExtensionSDK
import NotchExtensionRuntime
import XCTest
@testable import NotchKit

@MainActor
final class PermissionRefreshCoordinatorTests: XCTestCase {
    private func identity() -> ExtensionIdentity {
        guard let id = try? ExtensionIdentity("com.notchkit.hud") else {
            fatalError("invalid identity")
        }
        return id
    }

    func testActiveFeatureIsDisabledWhenPermissionIsRevoked() {
        let id = identity()
        var disables = 0

        PermissionRefreshCoordinator.disableActiveFeatureIfRevoked(
            feature: id,
            isEnabled: { _ in true },
            phase: { _ in .active },
            isPermissionGranted: { false },
            disable: { _ in disables += 1 }
        )

        XCTAssertEqual(disables, 1)
    }

    func testInitialPermissionGateRemainsEnabledWhileAccessIsMissing() {
        let id = identity()
        var disables = 0

        PermissionRefreshCoordinator.disableActiveFeatureIfRevoked(
            feature: id,
            isEnabled: { _ in true },
            phase: { _ in .requiresPermission("accessibility permission required") },
            isPermissionGranted: { false },
            disable: { _ in disables += 1 }
        )

        XCTAssertEqual(disables, 0)
    }

    func testActiveFeatureIsUnchangedWhilePermissionIsGranted() {
        let id = identity()
        var disables = 0

        PermissionRefreshCoordinator.disableActiveFeatureIfRevoked(
            feature: id,
            isEnabled: { _ in true },
            phase: { _ in .active },
            isPermissionGranted: { true },
            disable: { _ in disables += 1 }
        )

        XCTAssertEqual(disables, 0)
    }

    /// Refresh after a grant re-attempts the feature exactly once, then becomes
    /// a no-op once it is active.
    func testRefreshAfterGrantActivatesEnabledBlockedFeatureOnce() {
        let id = identity()
        var phase: ExtensionRuntimePhase = .requiresPermission("accessibility permission required")
        var retries = 0

        let refresh = {
            PermissionRefreshCoordinator.reconcileIfGranted(
                feature: id,
                isEnabled: { _ in true },
                phase: { _ in phase },
                isPermissionGranted: { true },
                retry: { _ in
                    retries += 1
                    phase = .active
                }
            )
        }

        refresh()
        XCTAssertEqual(retries, 1)

        refresh()
        XCTAssertEqual(retries, 1, "refreshing an active feature must be a no-op")
    }

    /// Refresh must never enable a disabled feature or start its services.
    func testRefreshWhileDisabledDoesNotActivate() {
        let id = identity()
        var retries = 0

        PermissionRefreshCoordinator.reconcileIfGranted(
            feature: id,
            isEnabled: { _ in false },
            phase: { _ in .requiresPermission("accessibility permission required") },
            isPermissionGranted: { true },
            retry: { _ in retries += 1 }
        )

        XCTAssertEqual(retries, 0)
    }

    func testRefreshWithoutGrantDoesNotActivate() {
        let id = identity()
        var retries = 0

        PermissionRefreshCoordinator.reconcileIfGranted(
            feature: id,
            isEnabled: { _ in true },
            phase: { _ in .requiresPermission("accessibility permission required") },
            isPermissionGranted: { false },
            retry: { _ in retries += 1 }
        )

        XCTAssertEqual(retries, 0)
    }

    /// A `.failed` feature is not a permission gate and is left alone.
    func testRefreshLeavesOperationalFailureAlone() {
        let id = identity()
        var retries = 0

        PermissionRefreshCoordinator.reconcileIfGranted(
            feature: id,
            isEnabled: { _ in true },
            phase: { _ in .failed("tap install failed") },
            isPermissionGranted: { true },
            retry: { _ in retries += 1 }
        )

        XCTAssertEqual(retries, 0)
    }
}
