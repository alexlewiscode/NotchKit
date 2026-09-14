//
//  NotchRouter.swift
//  NotchExtensionRuntime
//
//  Per-display selection of the active open destination.
//

import Combine
import NotchExtensionSDK
import SwiftUI

/// Selects the active open-notch destination for one display.
///
/// Each display has its own router, so selecting a destination on one display
/// does not change another. The router reads live contributions from the
/// `ContributionStore` and never presents a destination whose extension is
/// disabled or whose availability predicate is false; it falls back to Home.
@MainActor
public final class NotchRouter: ObservableObject {
    /// The display this router belongs to.
    public let displayID: DisplayID
    /// The id of the Home destination. Always a valid fallback.
    public let homeID: DestinationID

    /// The currently selected destination id.
    @Published public private(set) var activeDestinationID: DestinationID

    private let contributions: ContributionStore
    private let manager: ExtensionManager
    private let onChanged: (() -> Void)?

    public init(
        displayID: DisplayID,
        homeID: DestinationID,
        contributions: ContributionStore,
        manager: ExtensionManager,
        onChanged: (() -> Void)? = nil
    ) {
        self.displayID = displayID
        self.homeID = homeID
        self.contributions = contributions
        self.manager = manager
        self.onChanged = onChanged
        self.activeDestinationID = homeID
    }

    /// All destinations that are currently enabled and available, in tab order.
    public var availableDestinations: [NotchOpenDestination] {
        contributions.openDestinations.filter(isAvailable)
    }

    /// Selects a destination by id, falling back to Home when unusable.
    public func select(_ id: DestinationID) {
        if let destination = contributions.openDestination(for: id), isAvailable(destination) {
            activeDestinationID = id
        } else {
            activeDestinationID = homeID
        }
        onChanged?()
    }

    /// Re-evaluates the active destination and falls back to Home if needed.
    public func refreshAvailability() {
        guard let destination = contributions.openDestination(for: activeDestinationID),
              isAvailable(destination)
        else {
            activeDestinationID = homeID
            onChanged?()
            return
        }
        onChanged?()
    }

    /// The view for the active destination, if any.
    public var activeDestinationView: AnyView? {
        destinationView(for: activeDestinationID)
    }

    /// The view for a destination id, if it is available.
    public func destinationView(for id: DestinationID) -> AnyView? {
        guard let destination = contributions.openDestination(for: id),
              isAvailable(destination)
        else {
            return nil
        }
        return destination.makeView()
    }

    private func isAvailable(_ destination: NotchOpenDestination) -> Bool {
        if let extensionID = contributions.extensionID(forDestination: destination.id),
           !manager.isEnabled(extensionID)
        {
            return false
        }
        return destination.isAvailable()
    }
}