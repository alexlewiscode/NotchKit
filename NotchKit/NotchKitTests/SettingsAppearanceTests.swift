import AppKit
import Defaults
import NotchExtensionSDK
import XCTest
@testable import NotchKit

@MainActor
final class SettingsAppearanceTests: XCTestCase {
    func testSidebarOrderTitlesAndSymbolsRemainStable() {
        XCTAssertEqual(
            SettingsSection.allCases,
            [.general, .appearance, .interaction, .extensions, .marketplace, .shortcuts, .about]
        )
        XCTAssertEqual(
            SettingsSection.allCases.map(\.title),
            ["General", "Appearance", "Interaction", "Extensions", "Marketplace", "Shortcuts", "About"]
        )

        for section in SettingsSection.allCases {
            XCTAssertNotNil(
                NSImage(systemSymbolName: section.systemImage, accessibilityDescription: nil),
                "Missing sidebar symbol for \(section.title)"
            )
        }
    }

    func testSettingsBrandAssetsAreCompiled() {
        XCTAssertNotNil(NSImage(named: "NotchKitBrand"))
        let menuBarImage = NSImage(named: "NotchKitMenuBar")
        XCTAssertNotNil(menuBarImage)
        XCTAssertEqual(menuBarImage?.isTemplate, true)
    }

    func testExtensionSearchMatchesNamesAndSummaries() {
        let fields: [String?] = ["Calendar & Reminders", "Events and reminders in your notch."]

        XCTAssertTrue(ExtensionsSearch.matches(query: "calendar", fields: fields))
        XCTAssertTrue(ExtensionsSearch.matches(query: "  REMINDERS ", fields: fields))
        XCTAssertTrue(ExtensionsSearch.matches(query: "", fields: fields))
        XCTAssertFalse(ExtensionsSearch.matches(query: "battery", fields: fields))
    }

    func testMarketplaceIsASeparateRootSection() throws {
        let id = try ExtensionIdentity("com.example.extension")
        XCTAssertNotEqual(SettingsSection.marketplace, SettingsSection.extensions)
        XCTAssertEqual(ExtensionsRoute.installed(id), ExtensionsRoute.installed(id))
    }

    func testFocusedShortcutOwnerMovesFirst() {
        XCTAssertEqual(ShortcutsOwner.ordered(focused: nil), [.notch, .media])
        XCTAssertEqual(ShortcutsOwner.ordered(focused: .media), [.media, .notch])
    }

    func testInteractionPresentationUsesStableSensitivityLabels() {
        XCTAssertEqual(SettingsBehavior.gestureSensitivityLabel(for: 100), "High")
        XCTAssertEqual(SettingsBehavior.gestureSensitivityLabel(for: 200), "Medium")
        XCTAssertEqual(SettingsBehavior.gestureSensitivityLabel(for: 300), "Low")
        XCTAssertTrue(SettingsBehavior.gesturesMustRemainEnabled(openNotchOnHover: false))
    }

    func testInteractionSettingsPersistThroughExistingDefaultsKeys() {
        let originalHoverDelay = Defaults[.minimumHoverDuration]
        let originalHaptics = Defaults[.enableHaptics]
        defer {
            Defaults[.minimumHoverDuration] = originalHoverDelay
            Defaults[.enableHaptics] = originalHaptics
        }

        Defaults[.minimumHoverDuration] = 0.7
        Defaults[.enableHaptics] = false

        XCTAssertEqual(Defaults[.minimumHoverDuration], 0.7, accuracy: 0.001)
        XCTAssertFalse(Defaults[.enableHaptics])
    }
}
