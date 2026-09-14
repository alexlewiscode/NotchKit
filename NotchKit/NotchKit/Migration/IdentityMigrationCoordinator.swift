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
//  - Completion is recorded only after validation succeeds, so a partial or
//    failed run is retried on the next launch.
//  - No settings values, bookmark data, or Shelf contents are logged.
//

import Foundation
import NotchExtensionSDK
import NotchExtensionRuntime

enum IdentityMigrationCoordinator {
    /// Set when the helper could not read the legacy container, so the app can
    /// offer an explicit user-authorized import instead of silently skipping.
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
            // Helper blocked or legacy container absent. Do not record
            // completion and do not overwrite anything; request explicit user
            // authorization to import instead.
            UserDefaults.standard.set(true, forKey: pendingImportDefaultsKey)
            return
        }

        let summary = apply(archive: archive, appSupport: appSupport)
        guard summary.isValidCompletion, let data = try? JSONEncoder().encode(summary) else {
            // Leave the marker absent so the migration is retried next launch.
            return
        }
        try? FileManager.default.createDirectory(at: markerDir, withIntermediateDirectories: true)
        try? data.write(to: marker, options: .atomic)
        UserDefaults.standard.set(false, forKey: pendingImportDefaultsKey)
    }

    /// Applies the archive to the new namespace. Pure enough to unit test with
    /// an injected archive; performs only additive writes.
    @discardableResult
    static func apply(archive: [String: Any], appSupport: URL) -> IdentityMigration.Summary {
        let defaults = UserDefaults.standard
        var migratedCount = 0
        var extensionStateMigrated = true

        if let base64 = archive["defaultsPlist"] as? String,
           let plistData = Data(base64Encoded: base64),
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
        }

        // Shelf data: copy once, never overwrite existing NotchKit data.
        var shelfCopied = true
        let shelfDir = appSupport
            .appendingPathComponent(NotchKitIdentity.shelfDirectoryName, isDirectory: true)
            .appendingPathComponent("Shelf", isDirectory: true)
        let shelfURL = shelfDir.appendingPathComponent("items.json")

        if let base64 = archive["shelfItems"] as? String, let shelfData = Data(base64Encoded: base64) {
            if !FileManager.default.fileExists(atPath: shelfURL.path) {
                try? FileManager.default.createDirectory(at: shelfDir, withIntermediateDirectories: true)
                try? shelfData.write(to: shelfURL, options: .atomic)
            }
            shelfCopied = FileManager.default.fileExists(atPath: shelfURL.path)
        }

        return IdentityMigration.Summary(
            defaultsMigrated: migratedCount,
            extensionStateMigrated: extensionStateMigrated,
            shelfItemsCopied: shelfCopied,
            invalidBookmarkCount: ShelfBookmarkVerifier.invalidBookmarkCount()
        )
    }
}