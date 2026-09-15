//
//  FeatureEnablementTests.swift
//  NotchKitTests
//
//  Authoritative feature enablement: legacy migration and settings-catalog
//  composition for the toggleable first-party features.
//

import NotchExtensionRuntime
import NotchExtensionSDK
import XCTest
@testable import NotchKit

@MainActor
final class FeatureEnablementTests: XCTestCase {
    private func makeManager(
        snapshot: ExtensionStateSnapshot? = nil
    ) -> ExtensionManager {
        let registry = ExtensionRegistry(hostVersion: ExtensionVersion(major: 1, minor: 0, patch: 0))
        return ExtensionManager(
            registry: registry,
            store: InMemoryExtensionStateStore(snapshot: snapshot)
        )
    }

    // MARK: - Migration

    func testMigrationSeedsFromLegacyWhenAuthoritativeValueAbsent() {
        let manager = makeManager()
        let legacy = LegacyFeatureMasters(shelf: true, calendar: false, hud: true, camera: true)

        let outcome = FeatureEnablementMigration.migrateIfNeeded(
            manager: manager, legacy: legacy, alreadyMigrated: false)

        XCTAssertEqual(outcome.seeded.count, 4)
        XCTAssertTrue(manager.isEnabled(BuiltInExtensionIDs.shelf))
        XCTAssertFalse(manager.isEnabled(BuiltInExtensionIDs.calendar))
        XCTAssertTrue(manager.isEnabled(BuiltInExtensionIDs.hud))
        XCTAssertTrue(manager.isEnabled(BuiltInExtensionIDs.camera))
    }

    func testMigrationPreservesAlreadySavedAuthoritativeState() {
        var snapshot = ExtensionStateSnapshot()
        snapshot.enabled[BuiltInExtensionIDs.calendar.rawValue] = true
        let manager = makeManager(snapshot: snapshot)

        let legacy = LegacyFeatureMasters(shelf: false, calendar: false, hud: false, camera: false)
        let outcome = FeatureEnablementMigration.migrateIfNeeded(
            manager: manager, legacy: legacy, alreadyMigrated: false)

        XCTAssertTrue(
            outcome.preserved.contains(BuiltInExtensionIDs.calendar),
            "an explicit saved choice must not be overwritten by a legacy default"
        )
        XCTAssertTrue(manager.isEnabled(BuiltInExtensionIDs.calendar))
    }

    func testMigrationIsSkippedWhenMarkerIsSet() {
        let manager = makeManager()
        let legacy = LegacyFeatureMasters(shelf: true, calendar: true, hud: true, camera: true)

        let outcome = FeatureEnablementMigration.migrateIfNeeded(
            manager: manager, legacy: legacy, alreadyMigrated: true)

        XCTAssertTrue(outcome.skippedAlreadyMigrated)
        XCTAssertFalse(manager.isEnabled(BuiltInExtensionIDs.shelf))
        XCTAssertFalse(manager.isEnabled(BuiltInExtensionIDs.calendar))
    }

    func testMigrationIsIdempotent() {
        let manager = makeManager()
        let legacy = LegacyFeatureMasters(shelf: true, calendar: true, hud: false, camera: true)

        _ = FeatureEnablementMigration.migrateIfNeeded(
            manager: manager, legacy: legacy, alreadyMigrated: false)
        let second = FeatureEnablementMigration.migrateIfNeeded(
            manager: manager, legacy: legacy, alreadyMigrated: false)

        XCTAssertTrue(second.seeded.isEmpty, "a second run must not reseed")
        XCTAssertEqual(second.preserved.count, 4)
    }

    /// Regression: Shelf already had an authoritative value from the previous
    /// milestone, defaulted to `true` for everyone, while the user-facing master
    /// was `boringShelf`. A user who had Shelf off must stay off after upgrade.
    func testMigrationShelfLegacyValueWinsOverDefaultedAuthoritativeValue() {
        var snapshot = ExtensionStateSnapshot()
        snapshot.enabled[BuiltInExtensionIDs.shelf.rawValue] = true  // came from the default
        let manager = makeManager(snapshot: snapshot)

        let legacy = LegacyFeatureMasters(shelf: false, calendar: false, hud: false, camera: false)
        let outcome = FeatureEnablementMigration.migrateIfNeeded(
            manager: manager, legacy: legacy, alreadyMigrated: false)

        XCTAssertTrue(outcome.seeded.contains(BuiltInExtensionIDs.shelf))
        XCTAssertFalse(manager.isEnabled(BuiltInExtensionIDs.shelf))
    }

    /// Other features must not have an existing authoritative value overridden.
    func testMigrationDoesNotOverrideExplicitNonShelfChoice() {
        var snapshot = ExtensionStateSnapshot()
        snapshot.enabled[BuiltInExtensionIDs.calendar.rawValue] = true
        let manager = makeManager(snapshot: snapshot)

        let legacy = LegacyFeatureMasters(shelf: true, calendar: false, hud: false, camera: false)
        _ = FeatureEnablementMigration.migrateIfNeeded(
            manager: manager, legacy: legacy, alreadyMigrated: false)

        XCTAssertTrue(manager.isEnabled(BuiltInExtensionIDs.calendar))
    }

    // MARK: - Preference preservation

    func testStoppingCalendarKeepsSelectionAndClearsTransientLists() async {
        let selectionStore = InMemoryCalendarSelectionStore(.selected(["a"]))
        let service = FakeCalendarService()
        service.calendarResults = [[makeCalendar("a"), makeCalendar("b", isReminder: true)]]
        let manager = CalendarManager(calendarService: service, selectionStore: selectionStore)

        await manager.reloadCalendarAndReminderLists()
        XCTAssertFalse(manager.allCalendars.isEmpty)

        manager.stop()

        XCTAssertEqual(
            selectionStore.selectionState.selectedIdentifiers, ["a"],
            "stopping must not touch the persisted selection"
        )
        XCTAssertTrue(manager.events.isEmpty)
        XCTAssertTrue(manager.allCalendars.isEmpty)
    }

    func testStoppingMediaResetsTransientPlaybackState() {
        let manager = MusicManager()
        manager.isPlaying = true
        manager.isPlayerIdle = false
        manager.songTitle = "Playing"
        manager.bundleIdentifier = "com.apple.Music"

        manager.stop()

        XCTAssertFalse(manager.isPlaying)
        XCTAssertTrue(manager.isPlayerIdle, "closed-notch idle content must be able to render again")
        XCTAssertNil(manager.bundleIdentifier)
        XCTAssertEqual(manager.elapsedTime, 0)
    }

    // MARK: - Identities

    func testToggleableFeatureIdentitiesAreDistinctAndStable() {
        let identities = [
            BuiltInExtensionIDs.shelf,
            BuiltInExtensionIDs.calendar,
            BuiltInExtensionIDs.media,
            BuiltInExtensionIDs.hud,
            BuiltInExtensionIDs.camera,
            BuiltInExtensionIDs.home,
        ]
        XCTAssertEqual(Set(identities).count, identities.count)
        XCTAssertEqual(BuiltInExtensionIDs.calendar.rawValue, "com.notchkit.calendar")
        XCTAssertEqual(BuiltInExtensionIDs.media.rawValue, "com.notchkit.media")
        XCTAssertEqual(BuiltInExtensionIDs.hud.rawValue, "com.notchkit.hud")
        XCTAssertEqual(BuiltInExtensionIDs.camera.rawValue, "com.notchkit.camera")
    }

    // MARK: - Settings catalog

    /// Builds the same catalog the runtime builds, minus the conditionally
    /// compiled Battery definition.
    private func makeCatalog() -> SettingsCatalog {
        let catalog = SettingsCatalog()
        let definitions = BuiltInExtensions.definitions() + LegacyFeatureSettings.definitions()
        let runtimeManaged: Set<FeatureSettingsID> = [
            FeatureSettingsID(BuiltInExtensionIDs.shelf.rawValue),
            LegacyFeatureSettings.calendarFeatureID,
            LegacyFeatureSettings.mediaFeatureID,
            LegacyFeatureSettings.hudFeatureID,
            LegacyFeatureSettings.cameraFeatureID,
        ]
        catalog.rebuild(
            from: definitions,
            runtimeManaged: runtimeManaged,
            order: [:],
            adapters: []
        )
        return catalog
    }

    func testEveryToggleableFeatureIsRuntimeManagedWithAnOwnerAndDestination() {
        let catalog = makeCatalog()
        let names = Set(catalog.entries.map(\.displayName))

        for expected in ["Shelf", "Calendar & Reminders", "Media", "HUD", "Camera Mirror"] {
            XCTAssertTrue(names.contains(expected), "missing catalog entry for \(expected)")
        }

        for entry in catalog.entries {
            XCTAssertEqual(entry.management, .runtimeManaged, "\(entry.displayName) is not toggleable")
            XCTAssertNotNil(entry.owner, "\(entry.displayName) has no lifecycle owner")
            XCTAssertEqual(entry.destinations.count, 1, "\(entry.displayName) should have one page")
        }
    }

    func testConfigurationStaysPresentRegardlessOfEnabledState() {
        let catalog = makeCatalog()
        // The catalog is built from definitions, not enabled state, so a
        // disabled feature still has a destination to open.
        let manager = makeManager()
        manager.setEnabled(false, for: BuiltInExtensionIDs.calendar)
        XCTAssertFalse(manager.isEnabled(BuiltInExtensionIDs.calendar))
        XCTAssertNotNil(catalog.entry(for: BuiltInExtensionIDs.calendarSettings))
    }
}
