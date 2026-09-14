//
//  PresentationCoordinator.swift
//  NotchExtensionRuntime
//
//  Owns one router per display and propagates contribution changes.
//

import Combine
import Foundation
import NotchExtensionSDK

/// App-wide presentation state with per-display routing.
///
/// Extension instances and host services are app-wide, but selection and
/// presentation are per-display: each `DisplayID` gets its own `NotchRouter`.
/// The coordinator publishes a revision whenever any router changes or live
/// contributions change, so SwiftUI observers re-render.
@MainActor
public final class PresentationCoordinator: ObservableObject {
    /// Bumped whenever routing or availability changes.
    @Published public private(set) var revision: Int = 0

    private let contributions: ContributionStore
    private let manager: ExtensionManager
    private let homeID: DestinationID
    private var routers: [DisplayID: NotchRouter] = [:]

    public init(
        contributions: ContributionStore,
        manager: ExtensionManager,
        homeID: DestinationID
    ) {
        self.contributions = contributions
        self.manager = manager
        self.homeID = homeID
    }

    /// The router for a display, creating it on first use.
    public func router(for display: DisplayID) -> NotchRouter {
        if let existing = routers[display] { return existing }
        let router = NotchRouter(
            displayID: display,
            homeID: homeID,
            contributions: contributions,
            manager: manager,
            onChanged: { [weak self] in self?.bump() }
        )
        routers[display] = router
        return router
    }

    /// Displays that currently have a router.
    public var displayIDs: [DisplayID] {
        routers.keys.sorted()
    }

    /// Drops a display's router.
    public func removeRouter(for display: DisplayID) {
        routers.removeValue(forKey: display)
        bump()
    }

    /// Re-evaluates every router after contributions or enabled state change.
    public func refreshAll() {
        for router in routers.values {
            router.refreshAvailability()
        }
        bump()
    }

    private func bump() {
        revision &+= 1
    }
}