//
//  FeatureEnablementMigration.swift
//  NotchKit
//
//  One-time, idempotent migration of legacy per-feature master preferences into
//  the authoritative extension enabled state.
//
//  Rules:
//  - Respect an already-saved authoritative value; never overwrite it.
//  - Seed a feature only when its legacy preference semantics match the whole
//    feature and no authoritative value exists yet.
//  - Leave legacy subpreferences in place; they are configuration, not masters,
//    and are never deleted or reset.
//  - Run once, guarded by a persisted marker, so re-running is a no-op.
//

import Defaults
import Foundation
import NotchExtensionSDK
import NotchExtensionRuntime

/// The legacy per-feature master preferences read during migration.
struct LegacyFeatureMasters: Equatable {
    var shelf: Bool
    var calendar: Bool
    var hud: Bool
    var camera: Bool

    /// The production values.
    static var current: LegacyFeatureMasters {
        LegacyFeatureMasters(
            shelf: Defaults[.boringShelf],
            calendar: Defaults[.showCalendar],
            hud: Defaults[.hudReplacement],
            camera: Defaults[.showMirror]
        )
    }
}

enum FeatureEnablementMigration {
    /// Defaults key recording that the migration has run.
    static let didMigrateKey = "didMigrateFeatureEnablement_v1"

    struct Outcome: Equatable {
        /// Feature identities whose authoritative value was seeded from a legacy
        /// preference.
        var seeded: [ExtensionIdentity] = []
        /// Feature identities already carrying an authoritative value that was
        /// left untouched.
        var preserved: [ExtensionIdentity] = []
        /// True when nothing was done because the migration had already run.
        var skippedAlreadyMigrated = false
    }

    /// Applies the migration to a manager.
    ///
    /// - Parameter force: used by tests to run the body without the persisted
    ///   marker.
    @discardableResult
    static func migrateIfNeeded(
        manager: ExtensionManager,
        legacy: LegacyFeatureMasters,
        alreadyMigrated: Bool,
        force: Bool = false
    ) -> Outcome {
        guard force || !alreadyMigrated else {
            return Outcome(skippedAlreadyMigrated: true)
        }

        var outcome = Outcome()
        let seeds: [(ExtensionIdentity, Bool)] = [
            (BuiltInExtensionIDs.shelf, legacy.shelf),
            (BuiltInExtensionIDs.calendar, legacy.calendar),
            (BuiltInExtensionIDs.hud, legacy.hud),
            (BuiltInExtensionIDs.camera, legacy.camera),
        ]

        for (identity, legacyValue) in seeds {
            if manager.state.enabled[identity.rawValue] == nil {
                manager.setEnabled(legacyValue, for: identity)
                outcome.seeded.append(identity)
            } else {
                outcome.preserved.append(identity)
            }
        }
        return outcome
    }

    /// Production entry point: reads the persisted marker and legacy values,
    /// applies the migration, and records that it ran.
    @discardableResult
    static func runIfNeeded(manager: ExtensionManager, defaults: UserDefaults = .standard) -> Outcome {
        let already = defaults.bool(forKey: didMigrateKey)
        let outcome = migrateIfNeeded(
            manager: manager,
            legacy: .current,
            alreadyMigrated: already
        )
        defaults.set(true, forKey: didMigrateKey)
        return outcome
    }
}
