//
//  ContributionStore.swift
//  NotchExtensionRuntime
//
//  Holds the contributions of currently active extensions.
//

import Foundation
import NotchExtensionSDK
import SwiftUI

/// Errors raised when activating contributions collide.
public enum ContributionStoreError: Error, Equatable {
    case duplicateDestinationID(DestinationID)
    case duplicateContributionID(ContributionID)
}

/// Registry of live contributions from activated extensions.
///
/// Renderers read only from this store, so a disabled or failed extension
/// contributes nothing. Contributions are added on activation and removed on
/// deactivation.
@MainActor
public final class ContributionStore {
    private var openByExtension: [ExtensionIdentity: [NotchOpenDestination]] = [:]
    private var closedByExtension: [ExtensionIdentity: [ClosedNotchContribution]] = [:]
    private var settingsByExtension: [ExtensionIdentity: [ExtensionSettingsDestination]] = [:]

    private var extensionByDestination: [DestinationID: ExtensionIdentity] = [:]
    private var extensionBySettings: [DestinationID: ExtensionIdentity] = [:]
    private var extensionByContribution: [ContributionID: ExtensionIdentity] = [:]

    public nonisolated init() {}

    /// Installs the contributions for one extension, replacing any previous set.
    public func set(
        open: [NotchOpenDestination],
        closed: [ClosedNotchContribution],
        settings: [ExtensionSettingsDestination],
        for id: ExtensionIdentity
    ) throws {
        removeContributions(for: id)

        var destinations = Set<DestinationID>()
        for destination in open {
            guard extensionByDestination[destination.id] == nil,
                  destinations.insert(destination.id).inserted
            else {
                throw ContributionStoreError.duplicateDestinationID(destination.id)
            }
        }
        for destination in settings {
            guard extensionBySettings[destination.id] == nil,
                  destinations.insert(destination.id).inserted
            else {
                throw ContributionStoreError.duplicateDestinationID(destination.id)
            }
        }

        var contributionIDs = Set<ContributionID>()
        for contribution in closed {
            guard extensionByContribution[contribution.id] == nil,
                  contributionIDs.insert(contribution.id).inserted
            else {
                throw ContributionStoreError.duplicateContributionID(contribution.id)
            }
        }

        openByExtension[id] = open
        closedByExtension[id] = closed
        settingsByExtension[id] = settings
        for destination in open { extensionByDestination[destination.id] = id }
        for destination in settings { extensionBySettings[destination.id] = id }
        for contribution in closed { extensionByContribution[contribution.id] = id }
    }

    /// Removes every contribution owned by an extension.
    public func removeContributions(for id: ExtensionIdentity) {
        for destination in openByExtension[id] ?? [] {
            extensionByDestination.removeValue(forKey: destination.id)
        }
        for destination in settingsByExtension[id] ?? [] {
            extensionBySettings.removeValue(forKey: destination.id)
        }
        for contribution in closedByExtension[id] ?? [] {
            extensionByContribution.removeValue(forKey: contribution.id)
        }
        openByExtension.removeValue(forKey: id)
        closedByExtension.removeValue(forKey: id)
        settingsByExtension.removeValue(forKey: id)
    }

    public func removeAll() {
        openByExtension.removeAll()
        closedByExtension.removeAll()
        settingsByExtension.removeAll()
        extensionByDestination.removeAll()
        extensionBySettings.removeAll()
        extensionByContribution.removeAll()
    }

    /// All open destinations, sorted by order, then title, then id.
    public var openDestinations: [NotchOpenDestination] {
        openByExtension.values
            .flatMap { $0 }
            .sorted { lhs, rhs in
                if lhs.order != rhs.order { return lhs.order < rhs.order }
                if lhs.title != rhs.title { return lhs.title < rhs.title }
                return lhs.id < rhs.id
            }
    }

    /// All settings destinations, sorted by title, then id.
    public var settingsDestinations: [ExtensionSettingsDestination] {
        settingsByExtension.values
            .flatMap { $0 }
            .sorted { lhs, rhs in
                if lhs.title != rhs.title { return lhs.title < rhs.title }
                return lhs.id < rhs.id
            }
    }

    /// All closed-notch contributions.
    public var closedNotchContributions: [ClosedNotchContribution] {
        closedByExtension.values.flatMap { $0 }
    }

    public func openDestination(for id: DestinationID) -> NotchOpenDestination? {
        openByExtension.values.flatMap { $0 }.first { $0.id == id }
    }

    public func settingsDestination(for id: DestinationID) -> ExtensionSettingsDestination? {
        settingsByExtension.values.flatMap { $0 }.first { $0.id == id }
    }

    public func extensionID(forDestination id: DestinationID) -> ExtensionIdentity? {
        extensionByDestination[id]
    }

    public func extensionID(forSettingsDestination id: DestinationID) -> ExtensionIdentity? {
        extensionBySettings[id]
    }

    public func extensionID(forContribution id: ContributionID) -> ExtensionIdentity? {
        extensionByContribution[id]
    }
}