//
//  SettingsCatalog.swift
//  NotchExtensionRuntime
//
//  Host-agnostic settings catalog core.
//
//  The host composes this catalog from lifecycle-independent
//  `ExtensionDefinition.settings` declarations plus its own legacy feature
//  adapters, and remains the authority for which features are runtime-managed
//  and in what order they appear. Keeping the pure core in the linked runtime
//  library makes catalog construction, duplicate prevention, and removal
//  testable without a running app.
//

import Combine
import Foundation
import NotchExtensionSDK

/// A stable host feature id used by the settings catalog and routes.
public struct FeatureSettingsID: Hashable, Identifiable, Sendable {
    public let rawValue: String
    public var id: String { rawValue }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// How the hub treats a feature's lifecycle.
public enum SettingsManagement: Hashable, Sendable {
    /// The extension runtime owns enable/disable and the hub shows a toggle.
    case runtimeManaged
    /// Configuration only: the hub must not present a lifecycle toggle.
    case configurationOnly
}

/// A catalog entry: one feature configuration page set reachable from the hub.
public struct SettingsCatalogEntry: Identifiable {
    public let id: FeatureSettingsID
    public let displayName: String
    public let iconSystemName: String
    /// `nil` for host-owned adapters that are not extension-backed.
    public let owner: ExtensionIdentity?
    public let management: SettingsManagement
    public let order: Int
    public let destinations: [ExtensionSettingsDestination]

    public init(
        id: FeatureSettingsID,
        displayName: String,
        iconSystemName: String,
        owner: ExtensionIdentity?,
        management: SettingsManagement,
        order: Int,
        destinations: [ExtensionSettingsDestination]
    ) {
        self.id = id
        self.displayName = displayName
        self.iconSystemName = iconSystemName
        self.owner = owner
        self.management = management
        self.order = order
        self.destinations = destinations
    }
}

/// The authoritative settings catalog for the Extensions hub.
@MainActor
public final class SettingsCatalog: ObservableObject {
    /// Catalog entries in presentation order.
    @Published public private(set) var entries: [SettingsCatalogEntry] = []

    /// Bumped whenever the catalog is rebuilt, so views can prune stale routes.
    @Published public private(set) var revision = UUID()

    public nonisolated init() {}

    /// Rebuilds the catalog from definitions and host adapters.
    ///
    /// - Parameters:
    ///   - definitions: registered extension definitions. Their `settings`
    ///     closures are evaluated here, never `makeInstance`.
    ///   - runtimeManaged: feature ids whose lifecycle the hub manages. All
    ///     other entries are configuration-only.
    ///   - order: explicit presentation order for definition-backed entries.
    ///   - adapters: host-owned entries for features that are not extracted.
    public func rebuild(
        from definitions: [ExtensionDefinition],
        runtimeManaged: Set<FeatureSettingsID> = [],
        order: [FeatureSettingsID: Int] = [:],
        adapters: [SettingsCatalogEntry] = []
    ) {
        var seenDestinations = Set<DestinationID>()
        var result: [SettingsCatalogEntry] = []

        for definition in definitions {
            let destinations = definition.settings()
                .filter { seenDestinations.insert($0.id).inserted }
            guard !destinations.isEmpty else { continue }
            let featureID = FeatureSettingsID(definition.id.rawValue)
            result.append(
                SettingsCatalogEntry(
                    id: featureID,
                    displayName: definition.metadata.displayName,
                    iconSystemName: definition.metadata.iconSystemName,
                    owner: definition.id,
                    management: runtimeManaged.contains(featureID)
                        ? .runtimeManaged : .configurationOnly,
                    order: order[featureID] ?? 1000,
                    destinations: destinations
                )
            )
        }

        for adapter in adapters {
            let destinations = adapter.destinations
                .filter { seenDestinations.insert($0.id).inserted }
            guard !destinations.isEmpty else { continue }
            result.append(
                SettingsCatalogEntry(
                    id: adapter.id,
                    displayName: adapter.displayName,
                    iconSystemName: adapter.iconSystemName,
                    owner: adapter.owner,
                    management: adapter.management,
                    order: adapter.order,
                    destinations: destinations
                )
            )
        }

        entries = result.sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
        revision = UUID()
    }

    /// The entry that owns a destination id.
    public func entry(for destinationID: DestinationID) -> SettingsCatalogEntry? {
        entries.first { entry in
            entry.destinations.contains { $0.id == destinationID }
        }
    }

    /// The destination for a destination id, if it is still in the catalog.
    public func destination(for destinationID: DestinationID) -> ExtensionSettingsDestination? {
        entry(for: destinationID)?.destinations.first { $0.id == destinationID }
    }

    /// Whether a destination id is still present in the catalog.
    public func isPresent(_ destinationID: DestinationID) -> Bool {
        entry(for: destinationID) != nil
    }

    /// Every destination id currently in the catalog.
    public var destinationIDs: Set<DestinationID> {
        Set(entries.flatMap { $0.destinations.map(\.id) })
    }
}
