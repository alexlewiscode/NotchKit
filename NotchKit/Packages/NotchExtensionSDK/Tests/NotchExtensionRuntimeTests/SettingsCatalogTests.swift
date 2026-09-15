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

    // MARK: Diagnostics

    func testMissingSettingsDeclarationIsDiagnosedWithoutInstantiation() throws {
        let id = try TestFactory.identity("com.notchkit.legacy")
        var instantiated = false
        let metadata = TestFactory.metadata(
            id: id,
            entryPoints: [
                ExtensionEntryPoint(id: "com.notchkit.settings.legacy", kind: .settingsDestination)
            ]
        )
        // A legacy definition that kept settings on the deprecated instance
        // method and supplies no definition-level declaration.
        let definition = ExtensionDefinition(metadata: metadata) { _ in
            instantiated = true
            return StaticExtension()
        }

        let catalog = SettingsCatalog()
        catalog.rebuild(from: [definition])

        XCTAssertTrue(catalog.entries.isEmpty)
        XCTAssertFalse(instantiated, "Diagnostics must not instantiate the extension")
        XCTAssertTrue(
            catalog.diagnostics.contains {
                $0.kind == .missingSettingsDeclaration(
                    featureID: FeatureSettingsID("com.notchkit.legacy"),
                    entryPointID: "com.notchkit.settings.legacy"
                )
            },
            "Expected a missing-settings-declaration diagnostic, got \(catalog.diagnostics)"
        )
    }

    func testUndeclaredSettingsDestinationIsDiagnosed() throws {
        let id = try TestFactory.identity("com.notchkit.alpha")
        // Metadata declares no entry points, but the definition supplies a page.
        let metadata = TestFactory.metadata(id: id)
        let destination = TestFactory.settingsDestination("com.notchkit.settings.alpha")
        let definition = ExtensionDefinition(
            metadata: metadata,
            settings: { [destination] },
            makeInstance: { _ in StaticExtension() }
        )

        let catalog = SettingsCatalog()
        catalog.rebuild(from: [definition])

        XCTAssertTrue(
            catalog.diagnostics.contains {
                $0.kind == .undeclaredSettingsDestination(
                    featureID: FeatureSettingsID("com.notchkit.alpha"),
                    destinationID: destination.id
                )
            }
        )
    }

    func testDuplicateFeatureIDKeepsFirstAndDiagnoses() throws {
        let catalog = SettingsCatalog()
        let first = try definition(
            "com.notchkit.alpha",
            settings: [TestFactory.settingsDestination("com.notchkit.settings.alpha")]
        )
        let adapter = SettingsCatalogEntry(
            id: FeatureSettingsID("com.notchkit.alpha"),
            displayName: "Duplicate",
            iconSystemName: "square",
            owner: nil,
            management: .configurationOnly,
            order: 1,
            destinations: [TestFactory.settingsDestination("com.notchkit.settings.alpha.other")]
        )

        catalog.rebuild(from: [first], adapters: [adapter])

        XCTAssertEqual(catalog.entries.count, 1)
        XCTAssertEqual(catalog.entries.first?.owner, first.id)
        XCTAssertTrue(
            catalog.diagnostics.contains {
                $0.kind == .duplicateFeatureID(FeatureSettingsID("com.notchkit.alpha"))
            }
        )
        XCTAssertTrue(
            catalog.diagnostics.contains {
                $0.kind == .duplicateFeatureID(FeatureSettingsID("com.notchkit.alpha"))
                    && $0.message.contains("keeping the earlier registration")
            },
            "A retained first registration should say it was kept: \(catalog.diagnostics)"
        )
    }

    func testDuplicateFeatureIDWhenFirstRegistrationWasRejectedDescribesActualPolicy() throws {
        let catalog = SettingsCatalog()
        let shared = TestFactory.settingsDestination("com.notchkit.settings.shared")
        // The first registration of alpha reserves the id but is dropped because
        // its only destination was already claimed by beta.
        let beta = try definition("com.notchkit.beta", settings: [shared])
        let alphaRejected = try definition("com.notchkit.alpha", settings: [shared])
        let empty = try definition("com.notchkit.empty", settings: [])

        let alphaAdapter = SettingsCatalogEntry(
            id: FeatureSettingsID("com.notchkit.alpha"),
            displayName: "Alpha duplicate",
            iconSystemName: "square",
            owner: nil,
            management: .configurationOnly,
            order: 1,
            destinations: [TestFactory.settingsDestination("com.notchkit.settings.alpha.other")]
        )

        catalog.rebuild(
            from: [beta, alphaRejected, empty],
            adapters: [alphaAdapter]
        )

        XCTAssertFalse(
            catalog.entries.contains { $0.id == FeatureSettingsID("com.notchkit.alpha") },
            "The rejected first registration must not produce an entry"
        )
        let duplicate = catalog.diagnostics.first {
            $0.kind == .duplicateFeatureID(FeatureSettingsID("com.notchkit.alpha"))
        }
        XCTAssertNotNil(duplicate)
        XCTAssertFalse(
            duplicate?.message.contains("keeping the earlier registration") ?? true,
            "The message must not claim a retained registration when the first was rejected"
        )
        XCTAssertTrue(
            duplicate?.message.contains("never reassigned") ?? false,
            "The message must describe that the id is not reassigned: \(String(describing: duplicate?.message))"
        )
    }

    func testOrderingIsDeterministicForEqualOrder() throws {
        let catalog = SettingsCatalog()
        let zeta = try definition(
            "com.notchkit.zeta",
            settings: [TestFactory.settingsDestination("com.notchkit.settings.zeta")]
        )
        let alpha = try definition(
            "com.notchkit.alpha",
            settings: [TestFactory.settingsDestination("com.notchkit.settings.alpha")]
        )

        catalog.rebuild(from: [zeta, alpha])

        XCTAssertEqual(
            catalog.entries.map(\.id.rawValue),
            ["com.notchkit.alpha", "com.notchkit.zeta"]
        )
    }

    func testRebuildClearsDiagnostics() throws {
        let id = try TestFactory.identity("com.notchkit.legacy")
        let metadata = TestFactory.metadata(
            id: id,
            entryPoints: [
                ExtensionEntryPoint(id: "com.notchkit.settings.legacy", kind: .settingsDestination)
            ]
        )
        let definition = ExtensionDefinition(metadata: metadata) { _ in StaticExtension() }
        let catalog = SettingsCatalog()

        catalog.rebuild(from: [definition])
        XCTAssertFalse(catalog.diagnostics.isEmpty)

        catalog.rebuild(from: [])
        XCTAssertTrue(catalog.diagnostics.isEmpty)
    }
}
