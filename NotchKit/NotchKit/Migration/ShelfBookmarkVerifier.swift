//
//  ShelfBookmarkVerifier.swift
//  NotchKit
//
//  Verifies Shelf file bookmarks after migration without logging paths or
//  contents. Bookmarks are treated as possibly valid: only bookmarks that fail
//  to resolve are counted, and they can be re-authorized by the user.
//

import Foundation

enum ShelfBookmarkVerifier {
    /// Counts Shelf file items whose security-scoped bookmark cannot be
    /// resolved under the current app identity.
    static func invalidBookmarkCount() -> Int {
        let items = ShelfPersistenceService.shared.load()
        var invalid = 0
        for item in items {
            guard case let .file(bookmarkData) = item.kind, !bookmarkData.isEmpty else { continue }
            var isStale = false
            let resolved = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if resolved == nil {
                invalid += 1
            }
        }
        return invalid
    }
}