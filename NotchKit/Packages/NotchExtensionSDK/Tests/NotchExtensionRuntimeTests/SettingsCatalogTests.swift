//
//  SettingsCatalogTests.swift
//  NotchExtensionRuntimeTests
//
//  Catalog construction, duplicate prevention, lifecycle-independent settings,
//  and removal/staleness tests.
//

import NotchExtensionSDK
import NotchExtensionRuntime
import XCTest

@MainActor
final class SettingsCatalogTests: XCTestCase {

    private func definition(
        _ raw: String,
        settings: [ExtensionSettingsDestination],
        onInstantiate: @escaping () -> Void = {}
    ) throws -> ExtensionDefinition {
        let id = try TestFactory.identity(raw)
        let metadata = TestFactory.metadata(
            id: id,
            entryPoints: settings.map {
                ExtensionEntryPoint(id: $0.id.rawValue, kind: .settingsDestination)
            }
        )
        return ExtensionDefinition(
            metadata: metadata,
            settings: { settings },
            makeInstance: { _ in
                onInstantiate()
                return StaticExtension()
            }
        )
    }

    func testCatalogBuildsDefinitionAndAdapterEntriesWithoutDuplicates() throws {
        let catalog = SettingsCatalog()
        let batterySettings = TestFactory.settingsDestination(
            "com.notchkit.settings.battery", title: "Battery")
        let shelfSettings = TestFactory.settingsDestination(
            "com.notchkit.settings.shelf", title: "Shelf")
        let calendarSettings = TestFactory.settingsDestination(
            "com.notchkit.settings.calendar", title: "Calendar")

        let battery = try definition("com.notchkit.battery", settings: [batterySettings])
        let shelf = try definition("com.notchkit.shelf", settings: [shelfSettings])

        let batteryID = FeatureSettingsID("com.notchkit.battery")
        let calendarID = FeatureSettingsID("com.notchkit.feature.calendar")
        let adapter = SettingsCatalogEntry(
            id: calendarID,
            displayName: "Calendar",
            iconSystemName: "calendar",
            owner: nil,
            management: .configurationOnly,
            order: 10,
            destinations: [calendarSettings]
        )

        catalog.rebuild(
            from: [battery, shelf],
            runtimeManaged: [batteryID],
            order: [batteryID: 0, FeatureSettingsID("com.notchkit.shelf"): 20],
            adapters: [adapter]
        )

        XCTAssertEqual(catalog.entries.count, 3)
        XCTAssertEqual(
            catalog.entries.map(\.id.rawValue),
            ["com.notchkit.battery", "com.notchkit.feature.calendar", "com.notchkit.shelf"]
        )
        XCTAssertEqual(catalog.entries.first(where: { $0.id == batteryID })?.management, .runtimeManaged)
        XCTAssertEqual(catalog.entries.first(where: { $0.id == FeatureSettingsID("com.notchkit.shelf") })?.management, .configurationOnly)
        XCTAssertEqual(catalog.destinationIDs.count, 3)
    }

    func testListingSettingsDoesNotInstantiateExtensions() throws {
        let catalog = SettingsCatalog()
        var instantiated = false
        let settings = TestFactory.settingsDestination("com.notchkit.settings.alpha")
        let definition = try definition("com.notchkit.alpha", settings: [settings]) {
            instantiated = true
        }

        catalog.rebuild(from: [definition])

        XCTAssertEqual(catalog.entries.count, 1)
        XCTAssertFalse(instantiated, "Building the catalog must not call makeInstance")
    }

    func testRebuildAfterRemovalLeavesNoStaleEntryOrDestination() throws {
        let catalog = SettingsCatalog()
        let settings = TestFactory.settingsDestination("com.notchkit.settings.alpha")
        let definition = try definition("com.notchkit.alpha", settings: [settings])

        catalog.rebuild(from: [definition])
        XCTAssertTrue(catalog.isPresent(settings.id))

        // The definition is removed: the catalog must be rebuilt with no entry,
        // no destination, and no dangling route.
        catalog.rebuild(from: [], runtimeManaged: [], order: [:], adapters: [])
        XCTAssertTrue(catalog.entries.isEmpty)
        XCTAssertFalse(catalog.isPresent(settings.id))
        XCTAssertNil(catalog.destination(for: settings.id))
    }

    func testDuplicateDestinationAcrossSourcesIsRegisteredOnce() throws {
        let catalog = SettingsCatalog()
        let settings = TestFactory.settingsDestination("com.notchkit.settings.shared")
        let definition = try definition("com.notchkit.alpha", settings: [settings])
        let adapter = SettingsCatalogEntry(
            id: FeatureSettingsID("com.notchkit.feature.shared"),
            displayName: "Shared",
            iconSystemName: "square",
            owner: nil,
            management: .configurationOnly,
            order: 5,
            destinations: [settings]
        )

        catalog.rebuild(from: [definition], adapters: [adapter])

        XCTAssertEqual(catalog.entries.count, 1, "A destination id must be registered once")
    }

    func testDefinitionSettingsDefaultToEmpty() throws {
        let id = try TestFactory.identity("com.notchkit.empty")
        let metadata = TestFactory.metadata(id: id)
        let definition = ExtensionDefinition(metadata: metadata) { _ in StaticExtension() }
        XCTAssertTrue(definition.settings().isEmpty)
    }
}
