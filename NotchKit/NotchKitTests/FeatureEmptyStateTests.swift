//
//  FeatureEmptyStateTests.swift
//  NotchKitTests
//
//  Focused tests for the all-off empty-state decision.
//

import NotchExtensionRuntime
import NotchExtensionSDK
import XCTest
@testable import NotchKit

final class FeatureEmptyStateTests: XCTestCase {
    private func identity(_ raw: String) -> ExtensionIdentity {
        guard let id = try? ExtensionIdentity(raw) else {
            fatalError("invalid identity \(raw)")
        }
        return id
    }

    /// The optional runtime features present in a full build.
    private var optionalFeatures: [ExtensionIdentity] {
        [
            BuiltInExtensionIDs.shelf,
            BuiltInExtensionIDs.calendar,
            BuiltInExtensionIDs.media,
            BuiltInExtensionIDs.hud,
            BuiltInExtensionIDs.camera,
        ]
    }

    /// Required infrastructure is not part of the decision: with only Home
    /// registered there are no optional features, so the empty state shows even
    /// though Home is always enabled.
    func testRequiredHomeOnlyShowsEmptyState() {
        let optional = OptionalFeatureEnablement.optionalFeatureIdentities(
            fromRegistered: [BuiltInExtensionIDs.home]
        )
        XCTAssertTrue(optional.isEmpty)
        XCTAssertTrue(
            OptionalFeatureEnablement.shouldShowEmptyState(
                optionalFeatures: optional,
                isEnabled: { _ in true },
                phase: { _ in .active }
            )
        )
    }

    func testAllOptionalFeaturesOffShowsEmptyState() {
        let enabled: Set<ExtensionIdentity> = []
        XCTAssertTrue(
            OptionalFeatureEnablement.shouldShowEmptyState(
                optionalFeatures: optionalFeatures,
                isEnabled: { enabled.contains($0) },
                phase: { _ in .inactive }
            )
        )
    }

    func testOneEnabledFeatureHidesEmptyState() {
        let enabled: Set<ExtensionIdentity> = [BuiltInExtensionIDs.calendar]
        XCTAssertFalse(
            OptionalFeatureEnablement.shouldShowEmptyState(
                optionalFeatures: optionalFeatures,
                isEnabled: { enabled.contains($0) },
                phase: { _ in .active }
            )
        )
    }

    /// A feature the user enabled stays "on" while it is blocked on a permission,
    /// has failed, or is still starting, so enablement guidance is not shown.
    func testEnabledButBlockedOrFailedFeatureIsNotOff() {
        let phases: [ExtensionRuntimePhase] = [
            .requiresPermission("Accessibility access is required."),
            .failed("Boom"),
            .activating,
            .active,
        ]
        for phase in phases {
            XCTAssertTrue(
                OptionalFeatureEnablement.isOn(isEnabled: true, phase: phase),
                "an enabled feature in \(phase) must count as on"
            )
        }

        XCTAssertFalse(
            OptionalFeatureEnablement.shouldShowEmptyState(
                optionalFeatures: optionalFeatures,
                isEnabled: { $0 == BuiltInExtensionIDs.hud },
                phase: { $0 == BuiltInExtensionIDs.hud ? .requiresPermission("Accessibility") : .inactive }
            )
        )
    }

    /// A feature being torn down stays "on" until it is fully inactive, so the
    /// empty state never flashes mid-transition.
    func testDeactivatingFeatureIsNotOff() {
        XCTAssertTrue(OptionalFeatureEnablement.isOn(isEnabled: false, phase: .deactivating))
        XCTAssertFalse(OptionalFeatureEnablement.isOn(isEnabled: false, phase: .inactive))
    }

    /// `NotchKitCoreOnly` does not register Battery, so it cannot keep the empty
    /// state hidden when everything else is off.
    func testBatteryAbsentInCoreOnlyDoesNotBlockEmptyState() {
        let battery = identity("com.notchkit.battery")
        let optional = OptionalFeatureEnablement.optionalFeatureIdentities(
            fromRegistered: optionalFeatures
        )
        XCTAssertFalse(optional.contains(battery))
        XCTAssertTrue(
            OptionalFeatureEnablement.shouldShowEmptyState(
                optionalFeatures: optional,
                isEnabled: { _ in false },
                phase: { _ in .inactive }
            )
        )
    }

    /// Battery drives a closed-notch indicator, not the expanded content, so an
    /// enabled Battery must not suppress the empty state.
    func testEnabledBatteryDoesNotBlockEmptyState() {
        let battery = identity("com.notchkit.battery")
        let optional = OptionalFeatureEnablement.optionalFeatureIdentities(
            fromRegistered: optionalFeatures + [battery]
        )
        XCTAssertFalse(optional.contains(battery))
        XCTAssertTrue(
            OptionalFeatureEnablement.shouldShowEmptyState(
                optionalFeatures: optional,
                isEnabled: { $0 == battery },
                phase: { _ in .inactive }
            ),
            "Battery on by itself must still show the hello empty state"
        )
    }

    func testHomeIsExcludedFromOptionalFeatures() {
        let optional = OptionalFeatureEnablement.optionalFeatureIdentities(
            fromRegistered: [BuiltInExtensionIDs.home] + optionalFeatures
        )
        XCTAssertFalse(optional.contains(BuiltInExtensionIDs.home))
        XCTAssertEqual(Set(optional), Set(optionalFeatures))
    }
}
