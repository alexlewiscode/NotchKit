//
//  NotchRouter.swift
//  NotchExtensionRuntime
//
//  Selects the active open destination by stable id.
//

import Combine
import NotchExtensionSDK
import SwiftUI

/// Selects the active open-notch destination by stable id.
///
/// The router is the replacement for switching over a closed enum. It never
/// presents a destination whose extension is disabled or whose `isAvailable`
/// predicate is false; in those cases it falls back to Home.
@MainActor
public final class NotchRouter: ObservableObject {
    /// The id of the Home destination. Always a valid fallback.
    public let homeID: DestinationID

    /// The currently selected destination id.
    @Published public private(set) var activeDestinationID: DestinationID

    private let registry: ExtensionRegistry
    private let manager: ExtensionManager

    public init(
        registry: ExtensionRegistry,
        manager: ExtensionManager,
        homeID: DestinationID
    ) {
        self.registry = registry
        self.manager = manager
        self.homeID = homeID
        self.activeDestinationID = homeID
    }

    /// All destinations that are currently enabled and available, in tab order.
    public var availableDestinations: [NotchOpenDestination] {
        registry.openDestinations.filter(isAvailable)
    }

    /// Selects a destination by id, falling back to Home when unusable.
    public func select(_ id: DestinationID) {
        if let destination = registry.openDestination(for: id), isAvailable(destination) {
            activeDestinationID = id
        } else {
            activeDestinationID = homeID
        }
    }

    /// Re-evaluates the active destination and falls back to Home if needed.
    public func refreshAvailability() {
        guard let destination = registry.openDestination(for: activeDestinationID),
              isAvailable(destination)
        else {
            activeDestinationID = homeID
            return
        }
    }

    /// The view for the active destination, if any.
    public var activeDestinationView: AnyView? {
        destinationView(for: activeDestinationID)
    }

    /// The view for a destination id, if it is available.
    public func destinationView(for id: DestinationID) -> AnyView? {
        guard let destination = registry.openDestination(for: id), isAvailable(destination) else {
            return nil
        }
        return destination.makeView()
    }

    private func isAvailable(_ destination: NotchOpenDestination) -> Bool {
        if let extensionID = registry.extensionID(forDestination: destination.id),
           !manager.isEnabled(extensionID)
        {
            return false
        }
        return destination.isAvailable()
    }
}
