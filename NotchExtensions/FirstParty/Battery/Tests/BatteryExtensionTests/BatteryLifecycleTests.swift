//
//  BatteryLifecycleTests.swift
//  BatteryExtensionTests
//
//  Lifecycle, disablement, re-enable, stale-event, preference, and
//  shared-service tests for the extracted Battery extension.
//

import XCTest
import NotchExtensionSDK
@testable import BatteryExtension

// MARK: - Test doubles

@MainActor
final class FakePowerSource: PowerSourceObserving {
    var current: BatterySnapshot = .unknown
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var activeCount = 0
    private var handler: (@MainActor (BatterySnapshot) -> Void)?

    func start(onChange: @escaping @MainActor (BatterySnapshot) -> Void) {
        startCount += 1
        activeCount += 1
        handler = onChange
    }

    func stop() {
        stopCount += 1
        activeCount = max(0, activeCount - 1)
        // Deliberately keep `handler`: tests use it to deliver a late event and
        // prove the monitor ignores stale callbacks after stop().
    }

    func emit(_ snapshot: BatterySnapshot) {
        current = snapshot
        handler?(snapshot)
    }
}

@MainActor
final class RecordingPresentationService: NotchPresentationService {
    var availableDisplays: [DisplayID] = [DisplayID("display.primary")]
    private(set) var requests: [(request: PresentationRequest, target: PresentationTarget)] = []

    func request(_ request: PresentationRequest, target: PresentationTarget) {
        requests.append((request, target))
    }
}

final class InMemoryStore: ExtensionScopedStore {
    var schemaVersion: Int = 1
    private var storage: [String: Data] = [:]
    func data(forKey key: String) -> Data? { storage[key] }
    func set(_ data: Data?, forKey key: String) { storage[key] = data }
}

@MainActor
final class StubPermissions: NotchPermissionService {
    func status(for permission: NotchPermission) -> NotchPermissionStatus { .notDetermined }
    func request(_ permission: NotchPermission) async -> NotchPermissionStatus { .notDetermined }
}

@MainActor
final class BatteryLifecycleTests: XCTestCase {

    private func makeContext() -> (
        context: ExtensionContext,
        bag: ExtensionCancellationBag,
        presentation: RecordingPresentationService
    ) {
        let bag = ExtensionCancellationBag()
        let presentation = RecordingPresentationService()
        let context = ExtensionContext(
            identity: BatteryIds.identity,
            cancellation: bag,
            presentation: presentation,
            store: InMemoryStore(),
            permissions: StubPermissions()
        )
        return (context, bag, presentation)
    }

    private func resetSettings() {
        UserDefaults.standard.removeObject(forKey: BatterySettingsKeys.showPowerStatusNotifications)
        UserDefaults.standard.removeObject(forKey: BatterySettingsKeys.showBatteryIndicator)
        UserDefaults.standard.removeObject(forKey: BatterySettingsKeys.showBatteryPercentage)
        UserDefaults.standard.removeObject(forKey: BatterySettingsKeys.showPowerStatusIcons)
    }

    // MARK: Activation

    func testActivateStartsExactlyOneObserver() async throws {
        resetSettings()
        let source = FakePowerSource()
        let monitor = BatteryMonitor(source: source)
        let (context, _, _) = makeContext()
        let sut = BatteryExtension(context: context, monitor: monitor)

        try await sut.activate()

        XCTAssertEqual(source.startCount, 1)
        XCTAssertEqual(source.activeCount, 1)
        XCTAssertTrue(monitor.isRunning)
    }

    func testActivateIsIdempotentForTheService() async throws {
        resetSettings()
        let source = FakePowerSource()
        let monitor = BatteryMonitor(source: source)
        let (context, _, _) = makeContext()
        let sut = BatteryExtension(context: context, monitor: monitor)

        try await sut.activate()
        // A second consumer observing the same monitor must not start another
        // observer: start() is idempotent.
        monitor.start()

        XCTAssertEqual(source.startCount, 1)
        XCTAssertEqual(source.activeCount, 1)
    }

    // MARK: Disablement

    func testDeactivateStopsObserverAndCancelsTeardown() async throws {
        resetSettings()
        let source = FakePowerSource()
        let monitor = BatteryMonitor(source: source)
        let (context, bag, _) = makeContext()
        let sut = BatteryExtension(context: context, monitor: monitor)

        try await sut.activate()
        sut.deactivate()

        XCTAssertEqual(source.activeCount, 0)
        XCTAssertEqual(source.stopCount, 1)
        XCTAssertFalse(monitor.isRunning)
        XCTAssertTrue(bag.isCancelled)
    }

    func testDeactivateIsIdempotentAfterPartialActivation() async throws {
        resetSettings()
        let source = FakePowerSource()
        let monitor = BatteryMonitor(source: source)
        let (context, _, _) = makeContext()
        let sut = BatteryExtension(context: context, monitor: monitor)

        try await sut.activate()
        sut.deactivate()
        sut.deactivate()

        XCTAssertEqual(source.activeCount, 0)
        XCTAssertFalse(monitor.isRunning)
    }

    func testStaleEventsAfterDeactivationAreIgnored() async throws {
        resetSettings()
        let source = FakePowerSource()
        let monitor = BatteryMonitor(source: source)
        let (context, _, _) = makeContext()
        let sut = BatteryExtension(context: context, monitor: monitor)

        try await sut.activate()
        let before = monitor.snapshot
        sut.deactivate()

        source.emit(
            BatterySnapshot(
                isPluggedIn: true,
                isCharging: true,
                currentCapacity: 42,
                maxCapacity: 100,
                isInLowPowerMode: false,
                timeToFullChargeMinutes: 30
            )
        )

        XCTAssertEqual(monitor.snapshot, before)
    }

    // MARK: Re-enable

    func testReenableDoesNotDuplicateServices() async throws {
        resetSettings()
        let source = FakePowerSource()
        let monitor = BatteryMonitor(source: source)
        let (context, _, _) = makeContext()
        let sut = BatteryExtension(context: context, monitor: monitor)

        try await sut.activate()
        sut.deactivate()
        try await sut.activate()

        // Two activations happened, but only one observer is ever live.
        XCTAssertEqual(source.activeCount, 1)
        XCTAssertTrue(monitor.isRunning)
    }

    // MARK: Preferences

    func testPreferencesArePreservedAcrossDisableEnable() async throws {
        resetSettings()
        BatterySettings.showBatteryIndicator = false
        BatterySettings.showPowerStatusNotifications = false

        let source = FakePowerSource()
        let monitor = BatteryMonitor(source: source)
        let (context, _, _) = makeContext()
        let sut = BatteryExtension(context: context, monitor: monitor)

        try await sut.activate()
        sut.deactivate()
        try await sut.activate()

        XCTAssertFalse(BatterySettings.showBatteryIndicator)
        XCTAssertFalse(BatterySettings.showPowerStatusNotifications)
        resetSettings()
    }

    // MARK: Presentation

    func testChargingChangeRequestsDisplayAwarePresentation() async throws {
        resetSettings()
        BatterySettings.showPowerStatusNotifications = true
        let source = FakePowerSource()
        let monitor = BatteryMonitor(source: source)
        let (context, _, presentation) = makeContext()
        let sut = BatteryExtension(context: context, monitor: monitor)

        try await sut.activate()
        source.emit(
            BatterySnapshot(
                isPluggedIn: true,
                isCharging: true,
                currentCapacity: 55,
                maxCapacity: 100,
                isInLowPowerMode: false,
                timeToFullChargeMinutes: 20
            )
        )

        XCTAssertEqual(presentation.requests.count, 1)
        guard case .showSneakPeek(let kind, _, _) = presentation.requests.first?.request else {
            return XCTFail("Expected a showSneakPeek request")
        }
        XCTAssertEqual(kind, "battery")
        XCTAssertEqual(presentation.requests.first?.target, .active)
        monitor.stop()
    }

    func testPresentationIsSuppressedWhenNotificationsDisabled() async throws {
        resetSettings()
        BatterySettings.showPowerStatusNotifications = false
        let source = FakePowerSource()
        let monitor = BatteryMonitor(source: source)
        let (context, _, presentation) = makeContext()
        let sut = BatteryExtension(context: context, monitor: monitor)

        try await sut.activate()
        source.emit(
            BatterySnapshot(
                isPluggedIn: true,
                isCharging: true,
                currentCapacity: 55,
                maxCapacity: 100,
                isInLowPowerMode: false,
                timeToFullChargeMinutes: 20
            )
        )

        XCTAssertTrue(presentation.requests.isEmpty)
        monitor.stop()
        resetSettings()
    }

    // MARK: Contributions

    func testContributionsExistOnlyWhileActive() async throws {
        resetSettings()
        let source = FakePowerSource()
        let monitor = BatteryMonitor(source: source)
        let (context, _, _) = makeContext()
        let sut = BatteryExtension(context: context, monitor: monitor)

        XCTAssertTrue(sut.closedNotchContributions().isEmpty)
        XCTAssertTrue(sut.settingsDestinations().isEmpty)

        try await sut.activate()
        XCTAssertEqual(sut.closedNotchContributions().count, 1)
        XCTAssertEqual(sut.settingsDestinations().count, 1)

        sut.deactivate()
        XCTAssertTrue(sut.closedNotchContributions().isEmpty)
        XCTAssertTrue(sut.settingsDestinations().isEmpty)
    }

    func testContributionAvailabilityMatchesLegacyGating() async throws {
        resetSettings()
        BatterySettings.showPowerStatusNotifications = true
        let source = FakePowerSource()
        let monitor = BatteryMonitor(source: source)
        let (context, _, _) = makeContext()
        let sut = BatteryExtension(context: context, monitor: monitor)
        try await sut.activate()

        guard let contribution = sut.closedNotchContributions().first else {
            return XCTFail("Missing contribution")
        }

        XCTAssertTrue(
            contribution.isAvailable(
                ClosedNotchRenderSnapshot(
                    isNotchOpen: false,
                    expandingViewKind: "battery",
                    isExpandingViewShown: true
                )
            )
        )
        XCTAssertFalse(
            contribution.isAvailable(
                ClosedNotchRenderSnapshot(
                    isNotchOpen: true,
                    expandingViewKind: "battery",
                    isExpandingViewShown: true
                )
            )
        )
        XCTAssertFalse(
            contribution.isAvailable(ClosedNotchRenderSnapshot())
        )
    }

    func testManifestDeclaresCapabilitiesMatchingEntryPoints() throws {
        let metadata = try BatteryManifest.metadata()
        XCTAssertEqual(metadata.id, BatteryIds.identity)
        XCTAssertEqual(metadata.artifactKind, .compiledIn)
        XCTAssertTrue(metadata.capabilities.contains(.closedNotchContribution))
        XCTAssertTrue(metadata.capabilities.contains(.settingsDestination))
        XCTAssertNoThrow(
            try ExtensionCompatibility.validate(
                metadata,
                hostVersion: ExtensionVersion(major: 1, minor: 0, patch: 0)
            )
        )
    }

    // MARK: Migration and robustness

    func testSettingsKeysMatchHistoricalHostKeys() {
        // These literals are the historical host UserDefaults keys. Changing
        // them without migrating stored values would silently reset preferences.
        XCTAssertEqual(BatterySettingsKeys.showPowerStatusNotifications, "showPowerStatusNotifications")
        XCTAssertEqual(BatterySettingsKeys.showBatteryIndicator, "showBatteryIndicator")
        XCTAssertEqual(BatterySettingsKeys.showBatteryPercentage, "showBatteryPercentage")
        XCTAssertEqual(BatterySettingsKeys.showPowerStatusIcons, "showPowerStatusIcons")
    }

    func testContributionUnavailableWhenNotificationsDisabled() async throws {
        resetSettings()
        BatterySettings.showPowerStatusNotifications = false
        let source = FakePowerSource()
        let monitor = BatteryMonitor(source: source)
        let (context, _, _) = makeContext()
        let sut = BatteryExtension(context: context, monitor: monitor)
        try await sut.activate()

        guard let contribution = sut.closedNotchContributions().first else {
            return XCTFail("Missing contribution")
        }
        XCTAssertFalse(
            contribution.isAvailable(
                ClosedNotchRenderSnapshot(
                    isNotchOpen: false,
                    expandingViewKind: "battery",
                    isExpandingViewShown: true
                )
            )
        )
        sut.deactivate()
        resetSettings()
    }

    func testPartialActivationFailureLeavesNoObserver() async throws {
        resetSettings()
        enum Boom: Error { case failed }
        let source = FakePowerSource()
        let monitor = BatteryMonitor(source: source)
        let (context, _, _) = makeContext()
        let sut = BatteryExtension(context: context, monitor: monitor)
        sut.activationFailure = Boom.failed

        do {
            try await sut.activate()
            XCTFail("Expected activation to throw")
        } catch {
            // Expected. The host would now call deactivate().
        }
        sut.deactivate()

        XCTAssertEqual(source.activeCount, 0)
        XCTAssertFalse(monitor.isRunning)
        XCTAssertTrue(sut.closedNotchContributions().isEmpty)
    }

    func testMonitorDoesNotReadPowerStateUntilStarted() {
        let source = FakePowerSource()
        source.current = BatterySnapshot(
            isPluggedIn: true,
            isCharging: true,
            currentCapacity: 90,
            maxCapacity: 100,
            isInLowPowerMode: false,
            timeToFullChargeMinutes: 5
        )
        let monitor = BatteryMonitor(source: source)
        // Construction must not sample the source.
        XCTAssertEqual(monitor.snapshot, .unknown)
        monitor.start()
        XCTAssertEqual(monitor.snapshot.currentCapacity, 90)
        monitor.stop()
    }
}