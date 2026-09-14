//
//  IdentityMigrationCoordinator.swift
//  NotchKit
//
//  One-time, non-destructive, retryable migration from the pre-NotchKit
//  (boringNotch) identity namespace to the NotchKit namespace.
//
//  Guarantees:
//  - Originals are never modified or deleted; values are only copied.
//  - Existing NotchKit data is never overwritten.
//  - Completion is recorded only after every expected source is validated, so a
//    partial, blocked, or failed run is retried on the next launch.
//  - No settings values, bookmark data, or Shelf contents are logged.
//

import Foundation
import NotchExtensionSDK
import NotchExtensionRuntime

enum IdentityMigrationCoordinator {
    /// Set when the legacy container exists but could not be fully read, so the
    /// app can offer an explicit user-authorized import instead of silently
    /// skipping data.
    static let pendingImportDefaultsKey = "com.notchkit.migration.pendingUserImport"

    private static let markerFileName = "identity-v1.done"

    /// Runs before the app reads persisted settings. Safe to call repeatedly.
    static func runBlockingIfNeeded() {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return }

        let markerDir = appSupport
            .appendingPathComponent(NotchKitIdentity.shelfDirectoryName, isDirectory: true)
            .appendingPathComponent("Migration", isDirectory: true)
        let marker = markerDir.appendingPathComponent(markerFileName)

        if FileManager.default.fileExists(atPath: marker.path) { return }

        guard let archive = LegacyIdentityArchiveReader.read() else {
            // Inconclusive: the helper did not respond. Do not record
            // completion and do not prompt (avoid nagging); retry next launch.
            return
        }

        // No legacy container at all: nothing to migrate. Record completion.
        if (archive["legacyContainerExists"] as? Bool) == false {
            writeMarker(
                IdentityMigration.Summary(
                    defaultsMigrated: 0, defaultsSatisfied: true,
                    extensionStateMigrated: true, shelfItemsCopied: true,
                    invalidBookmarkCount: 0
                ),
                markerDir: markerDir, marker: marker
            )
            UserDefaults.standard.set(false, forKey: pendingImportDefaultsKey)
            return
        }

        let summary = apply(archive: archive, appSupport: appSupport)
        if summary.isValidCompletion {
            writeMarker(summary, markerDir: markerDir, marker: marker)
            UserDefaults.standard.set(false, forKey: pendingImportDefaultsKey)
        } else {
            // Legacy data exists but some source could not be handled. Leave the
            // marker absent (retry) and offer an explicit import this session.
            UserDefaults.standard.set(true, forKey: pendingImportDefaultsKey)
        }
    }

    private static func writeMarker(_ summary: IdentityMigration.Summary, markerDir: URL, marker: URL) {
        guard let data = try? JSONEncoder().encode(summary) else { return }
        try? FileManager.default.createDirectory(at: markerDir, withIntermediateDirectories: true)
        try? data.write(to: marker, options: .atomic)
    }

    /// Applies the archive to the new namespace. Only additive writes are
    /// performed. Each source reports whether it was satisfied so the caller can
    /// avoid recording a partial run as complete.
    static func apply(archive: [String: Any], appSupport: URL) -> IdentityMigration.Summary {
        let defaults = UserDefaults.standard
        var migratedCount = 0
        var defaultsSatisfied = true
        var extensionStateMigrated = true

        if (archive["defaultsUnreadable"] as? Bool) == true {
            defaultsSatisfied = false
        } else if let base64 = archive["defaultsPlist"] as? String {
            if let plistData = Data(base64Encoded: base64),
               let legacy = (try? PropertyListSerialization.propertyList(
                   from: plistData, options: [], format: nil
               )) as? [String: Any] {

                let missing = IdentityMigration.missingDefaults(legacy: legacy) { key in
                    defaults.object(forKey: key) != nil
                }
                for (key, value) in missing {
                    defaults.set(value, forKey: key)
                    migratedCount += 1
                }

                if defaults.data(forKey: NotchKitIdentity.extensionStateDefaultsKey) == nil,
                   let legacyState = legacy[NotchKitIdentity.Legacy.extensionStateDefaultsKey] as? Data {
                    if let migratedState = IdentityMigration.migrateExtensionStateData(legacyState) {
                        defaults.set(migratedState, forKey: NotchKitIdentity.extensionStateDefaultsKey)
                    } else {
                        extensionStateMigrated = false
                    }
                }
            } else {
                // The helper reported a defaults file but it was not a readable
                // property list. Do not treat this as success.
                defaultsSatisfied = false
            }
        }

        // Shelf data: copy once, never overwrite existing NotchKit data.
        var shelfSatisfied = true
        let shelfDir = appSupport
            .appendingPathComponent(NotchKitIdentity.shelfDirectoryName, isDirectory: true)
            .appendingPathComponent("Shelf", isDirectory: true)
        let shelfURL = shelfDir.appendingPathComponent("items.json")

        if (archive["shelfUnreadable"] as? Bool) == true {
            shelfSatisfied = false
        } else if let base64 = archive["shelfItems"] as? String {
            if let shelfData = Data(base64Encoded: base64) {
                if !FileManager.default.fileExists(atPath: shelfURL.path) {
                    try? FileManager.default.createDirectory(at: shelfDir, withIntermediateDirectories: true)
                    try? shelfData.write(to: shelfURL, options: .atomic)
                }
                shelfSatisfied = FileManager.default.fileExists(atPath: shelfURL.path)
            } else {
                shelfSatisfied = false
            }
        }

        return IdentityMigration.Summary(
            defaultsMigrated: migratedCount,
            defaultsSatisfied: defaultsSatisfied,
            extensionStateMigrated: extensionStateMigrated,
            shelfItemsCopied: shelfSatisfied,
            invalidBookmarkCount: ShelfBookmarkVerifier.invalidBookmarkCount()
        )
    }
}