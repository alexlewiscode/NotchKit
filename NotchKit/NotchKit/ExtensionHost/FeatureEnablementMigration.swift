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
        // `shelf` is special: it already existed as a registered extension in the
        // previous milestone with `defaultEnabled == true`, so every install has a
        // persisted authoritative value that came from the default, not from a
        // user choice. The user-facing master for Shelf was `boringShelf`, so the
        // legacy value must win once. Every other feature had no authoritative
        // value at all, so an existing value is a genuine user choice.
        let seeds: [(identity: ExtensionIdentity, legacyValue: Bool, overridesExisting: Bool)] = [
            (BuiltInExtensionIDs.shelf, legacy.shelf, true),
            (BuiltInExtensionIDs.calendar, legacy.calendar, false),
            (BuiltInExtensionIDs.hud, legacy.hud, false),
            (BuiltInExtensionIDs.camera, legacy.camera, false),
        ]

        for seed in seeds {
            let existing = manager.state.enabled[seed.identity.rawValue]
            if existing == nil || (seed.overridesExisting && existing != seed.legacyValue) {
                manager.setEnabled(seed.legacyValue, for: seed.identity)
                outcome.seeded.append(seed.identity)
            } else {
                outcome.preserved.append(seed.identity)
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
