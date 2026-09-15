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
import os

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

/// A nonfatal catalog construction diagnostic.
///
/// These surface developer mistakes (a definition whose declared settings entry
/// point has no matching settings declaration, or id collisions) without ever
/// crashing the app or activating an extension.
public struct SettingsCatalogDiagnostic: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Metadata declares a settings destination entry point, but the
        /// definition's `settings` declaration provides no destination with that
        /// id.
        case missingSettingsDeclaration(featureID: FeatureSettingsID, entryPointID: String)
        /// A declared settings destination id is not among the metadata entry
        /// points (undeclared identity).
        case undeclaredSettingsDestination(featureID: FeatureSettingsID, destinationID: DestinationID)
        /// Two definition/adapter entries claim the same feature id. The later
        /// one is dropped; unrelated feature settings are never merged.
        case duplicateFeatureID(FeatureSettingsID)
        /// Two entries provide the same destination id. The later one is dropped.
        case duplicateDestinationID(DestinationID, featureID: FeatureSettingsID)
    }

    public let kind: Kind
    public let message: String

    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }
}

/// The authoritative settings catalog for the Extensions hub.
@MainActor
public final class SettingsCatalog: ObservableObject {
    /// Catalog entries in presentation order.
    @Published public private(set) var entries: [SettingsCatalogEntry] = []

    /// Bumped whenever the catalog is rebuilt, so views can prune stale routes.
    @Published public private(set) var revision = UUID()

    /// Nonfatal diagnostics produced by the most recent rebuild.
    public private(set) var diagnostics: [SettingsCatalogDiagnostic] = []

    private let logger = Logger(subsystem: "com.notchkit.app", category: "SettingsCatalog")

    public nonisolated init() {}

    /// Rebuilds the catalog from definitions and host adapters.
    ///
    /// Collision policy: a feature id belongs to the first registration that
    /// reaches the id check (definitions before adapters). That registration
    /// keeps the id even if it is later rejected for producing no destinations,
    /// so the id is never reassigned to a later duplicate; the later duplicate is
    /// dropped with a diagnostic rather than merging unrelated settings.
    /// Ordering is deterministic (explicit order, then display name, then id).
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
        diagnostics = []
        var seenFeatureIDs = Set<FeatureSettingsID>()
        var retainedFeatureIDs = Set<FeatureSettingsID>()
        var seenDestinations = Set<DestinationID>()
        var result: [SettingsCatalogEntry] = []

        for definition in definitions {
            let featureID = FeatureSettingsID(definition.id.rawValue)
            let declaredSettings = definition.settings()
            diagnoseEntryPointContract(
                featureID: featureID,
                metadata: definition.metadata,
                declared: declaredSettings
            )

            guard !declaredSettings.isEmpty else { continue }

            guard seenFeatureIDs.insert(featureID).inserted else {
                record(
                    .duplicateFeatureID(featureID),
                    duplicateFeatureMessage(
                        featureID,
                        earlierWasRetained: retainedFeatureIDs.contains(featureID)
                    )
                )
                continue
            }

            let destinations = uniqueDestinations(
                declaredSettings,
                featureID: featureID,
                seen: &seenDestinations
            )
            guard !destinations.isEmpty else { continue }

            retainedFeatureIDs.insert(featureID)
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
            guard seenFeatureIDs.insert(adapter.id).inserted else {
                record(
                    .duplicateFeatureID(adapter.id),
                    duplicateFeatureMessage(
                        adapter.id,
                        earlierWasRetained: retainedFeatureIDs.contains(adapter.id)
                    )
                )
                continue
            }

            let destinations = uniqueDestinations(
                adapter.destinations,
                featureID: adapter.id,
                seen: &seenDestinations
            )
            guard !destinations.isEmpty else { continue }

            retainedFeatureIDs.insert(adapter.id)
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
            let nameOrder = lhs.displayName.localizedStandardCompare(rhs.displayName)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return lhs.id.rawValue < rhs.id.rawValue
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

    // MARK: - Helpers

    private func diagnoseEntryPointContract(
        featureID: FeatureSettingsID,
        metadata: ExtensionMetadata,
        declared: [ExtensionSettingsDestination]
    ) {
        let declaredIDs = Set(declared.map { $0.id.rawValue })
        let entryPointIDs = Set(
            metadata.entryPoints
                .filter { $0.kind == .settingsDestination }
                .map(\.id)
        )

        for entryPointID in entryPointIDs where !declaredIDs.contains(entryPointID) {
            record(
                .missingSettingsDeclaration(
                    featureID: featureID,
                    entryPointID: entryPointID
                ),
                "Extension '\(featureID.rawValue)' declares settings destination "
                    + "'\(entryPointID)' in its metadata but supplies no matching "
                    + "ExtensionDefinition.settings declaration; that page is unreachable. "
                    + "Move it from settingsDestinations() onto ExtensionDefinition.settings."
            )
        }

        for destination in declared where !entryPointIDs.contains(destination.id.rawValue) {
            record(
                .undeclaredSettingsDestination(
                    featureID: featureID,
                    destinationID: destination.id
                ),
                "Extension '\(featureID.rawValue)' declares a settings page "
                    + "'\(destination.id.rawValue)' that is not listed as a settings-destination "
                    + "entry point in its metadata."
            )
        }
    }

    /// The diagnostic text depends on whether the id's first registration became
    /// a catalog entry. An earlier registration can reserve an id and still be
    /// dropped (for example when every destination was a duplicate), in which
    /// case the later duplicate is also ignored rather than reassigning the id.
    private func duplicateFeatureMessage(
        _ featureID: FeatureSettingsID,
        earlierWasRetained: Bool
    ) -> String {
        if earlierWasRetained {
            return "Duplicate feature id '\(featureID.rawValue)'; keeping the earlier registration."
        }
        return "Duplicate feature id '\(featureID.rawValue)'; an earlier registration reserved "
            + "this id but produced no entry, so this duplicate is also ignored. Feature ids are "
            + "first-come and are never reassigned."
    }

    private func uniqueDestinations(
        _ destinations: [ExtensionSettingsDestination],
        featureID: FeatureSettingsID,
        seen: inout Set<DestinationID>
    ) -> [ExtensionSettingsDestination] {
        destinations.filter { destination in
            guard seen.insert(destination.id).inserted else {
                record(
                    .duplicateDestinationID(destination.id, featureID: featureID),
                    "Destination id '\(destination.id.rawValue)' was already registered; "
                        + "dropping the duplicate from '\(featureID.rawValue)'."
                )
                return false
            }
            return true
        }
    }

    private func record(_ kind: SettingsCatalogDiagnostic.Kind, _ message: String) {
        diagnostics.append(SettingsCatalogDiagnostic(kind: kind, message: message))
        logger.warning("SettingsCatalog: \(message, privacy: .public)")
    }
}
