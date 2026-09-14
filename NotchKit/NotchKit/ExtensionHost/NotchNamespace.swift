//
//  NotchNamespace.swift
//  NotchKit
//
//  Environment key used to share the album-art namespace with extension views.
//

import SwiftUI

private struct NotchAlbumArtNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// The namespace used for album-art match-geometry animations.
    ///
    /// `ContentView` injects this so extension-provided open destinations can
    /// participate in the closed-to-open album art transition without capturing
    /// view-local state in their factories.
    var notchAlbumArtNamespace: Namespace.ID? {
        get { self[NotchAlbumArtNamespaceKey.self] }
        set { self[NotchAlbumArtNamespaceKey.self] = newValue }
    }
}