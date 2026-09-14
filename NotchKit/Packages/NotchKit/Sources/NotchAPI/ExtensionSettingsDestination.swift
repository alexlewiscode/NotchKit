//
//  ExtensionSettingsDestination.swift
//  NotchAPI
//
//  A declarative settings page reachable from the Extensions hub.
//

import SwiftUI

/// A settings destination an extension makes available to the Extensions hub.
///
/// Phase 1 keeps existing feature settings where they are. The hub only needs a
/// route to a declared destination.
public struct ExtensionSettingsDestination: Identifiable {
    /// Stable identity for routing.
    public let id: DestinationID
    /// User-visible title.
    public let title: String
    /// SF Symbol used for the icon.
    public let iconSystemName: String
    /// Whether the destination can currently be shown.
    public let isAvailable: () -> Bool
    /// The view factory. Core is responsible for hosting the returned view.
    public let makeView: () -> AnyView

    public init(
        id: DestinationID,
        title: String,
        iconSystemName: String,
        isAvailable: @escaping () -> Bool,
        makeView: @escaping () -> AnyView
    ) {
        self.id = id
        self.title = title
        self.iconSystemName = iconSystemName
        self.isAvailable = isAvailable
        self.makeView = makeView
    }
}
