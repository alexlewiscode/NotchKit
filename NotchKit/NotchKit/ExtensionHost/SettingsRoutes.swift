//
//  SettingsRoutes.swift
//  NotchKit
//
//  Typed settings navigation. The sidebar selection, extension detail
//  destinations, and shortcuts focus are all value types so routes can be
//  compared, pruned, and tested without string matching.
//
//  The catalog core (`FeatureSettingsID`, `SettingsManagement`,
//  `SettingsCatalogEntry`, `SettingsCatalog`) lives in the linked runtime
//  package so it can be unit-tested; the host owns the policy that populates it.
//

import NotchExtensionRuntime
import NotchExtensionSDK
import SwiftUI

/// The sections of the Settings sidebar.
enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case general
    case appearance
    case interaction
    case extensions
    case marketplace
    case shortcuts
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .appearance: return String(localized: "Appearance")
        case .interaction: return String(localized: "Interaction")
        case .extensions: return String(localized: "Extensions")
        case .marketplace: return String(localized: "Marketplace")
        case .shortcuts: return String(localized: "Shortcuts")
        case .about: return String(localized: "About")
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gear"
        case .appearance: return "eye"
        case .interaction: return "hand.tap"
        case .extensions: return "puzzlepiece.extension"
        case .marketplace: return "storefront"
        case .shortcuts: return "keyboard"
        case .about: return "info.circle"
        }
    }
}

/// The feature owner a shortcut belongs to.
enum ShortcutsOwner: String, CaseIterable, Identifiable, Hashable {
    case notch
    case media

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notch: return String(localized: "Notch")
        case .media: return String(localized: "Media")
        }
    }

    /// Places a deep-linked shortcut group first without changing the stable
    /// declaration order used by ordinary sidebar navigation.
    static func ordered(focused owner: ShortcutsOwner?) -> [ShortcutsOwner] {
        guard let owner else { return allCases }
        return [owner] + allCases.filter { $0 != owner }
    }
}

/// A route into an extension's configuration detail.
struct ExtensionSettingsRoute: Hashable {
    let featureID: FeatureSettingsID
    let destinationID: DestinationID
}

extension SettingsCatalog {
    /// Removes routes whose destination is no longer in the catalog.
    func prune(_ path: [ExtensionSettingsRoute]) -> [ExtensionSettingsRoute] {
        path.filter { isPresent($0.destinationID) }
    }
}

/// Action used by feature detail pages to jump to the central Shortcuts page.
struct OpenShortcutsAction {
    let handler: (ShortcutsOwner) -> Void

    func callAsFunction(_ owner: ShortcutsOwner) {
        handler(owner)
    }
}

private struct OpenShortcutsActionKey: EnvironmentKey {
    static let defaultValue = OpenShortcutsAction { _ in }
}

extension EnvironmentValues {
    /// Injected by the Extensions hub so feature pages can focus the central
    /// Shortcuts page on their owner without capturing the parent view.
    var openShortcuts: OpenShortcutsAction {
        get { self[OpenShortcutsActionKey.self] }
        set { self[OpenShortcutsActionKey.self] = newValue }
    }
}

enum SettingsBehavior {
    static func gestureSensitivityLabel(for value: CGFloat) -> String {
        if value <= 100 { return String(localized: "High") }
        if value <= 200 { return String(localized: "Medium") }
        return String(localized: "Low")
    }

    static func gesturesMustRemainEnabled(openNotchOnHover: Bool) -> Bool {
        !openNotchOnHover
    }
}
