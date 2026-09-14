//
//  LegacyImportFlow.swift
//  NotchKit
//
//  Explicit, user-authorized import used only when automatic migration could
//  not read the pre-NotchKit container. Nothing is overwritten and the user
//  chooses the file explicitly.
//

import AppKit
import NotchExtensionSDK

enum LegacyImportFlow {
    /// Presents the import prompt if automatic migration could not complete.
    @MainActor
    static func presentIfNeeded() {
        guard UserDefaults.standard.bool(forKey: IdentityMigrationCoordinator.pendingImportDefaultsKey) else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "Import existing boringNotch data?"
        alert.informativeText = """
        NotchKit could not automatically read your previous settings and Shelf \
        items. You can choose your old Shelf items file to import it. Existing \
        NotchKit data is never overwritten.
        """
        alert.addButton(withTitle: "Import…")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the old Shelf items.json file"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        importShelfItems(from: url)
    }

    /// Copies the selected Shelf items file into the NotchKit Shelf directory
    /// only if no NotchKit Shelf data exists yet.
    @discardableResult
    static func importShelfItems(from source: URL) -> Bool {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return false }

        let shelfDir = appSupport
            .appendingPathComponent(NotchKitIdentity.shelfDirectoryName, isDirectory: true)
            .appendingPathComponent("Shelf", isDirectory: true)
        let destination = shelfDir.appendingPathComponent("items.json")

        guard !FileManager.default.fileExists(atPath: destination.path),
              let data = try? Data(contentsOf: source) else {
            return false
        }
        do {
            try FileManager.default.createDirectory(at: shelfDir, withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
            UserDefaults.standard.set(false, forKey: IdentityMigrationCoordinator.pendingImportDefaultsKey)
            return true
        } catch {
            return false
        }
    }
}