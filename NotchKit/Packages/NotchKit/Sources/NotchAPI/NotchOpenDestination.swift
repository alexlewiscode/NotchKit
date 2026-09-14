//
//  NotchOpenDestination.swift
//  NotchAPI
//
//  A declarative open-notch tab.
//

import SwiftUI

/// A destination that can be shown while the notch is open.
///
/// Extensions declare destinations; core owns the window, geometry, animation,
/// and tab chrome that presents them.
public struct NotchOpenDestination: Identifiable {
    /// Stable identity for routing and persistence.
    public let id: DestinationID
    /// User-visible title.
    public let title: String
    /// SF Symbol used for the tab icon.
    public let iconSystemName: String
    /// Ordering hint; lower values sort first.
    public let order: Int
    /// Whether the destination can currently be shown.
    public let isAvailable: () -> Bool
    /// The view factory. Core is responsible for hosting the returned view.
    public let makeView: () -> AnyView

    public init(
        id: DestinationID,
        title: String,
        iconSystemName: String,
        order: Int,
        isAvailable: @escaping () -> Bool,
        makeView: @escaping () -> AnyView
    ) {
        self.id = id
        self.title = title
        self.iconSystemName = iconSystemName
        self.order = order
        self.isAvailable = isAvailable
        self.makeView = makeView
    }
}
