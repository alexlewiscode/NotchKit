//
//  ExtensionRegistry.swift
//  NotchExtensions
//
//  Validates and stores first-party extension descriptors.
//

import Foundation
import NotchAPI

/// Errors raised while registering descriptors.
public enum ExtensionRegistryError: Error, Equatable {
    case duplicateExtensionID(ExtensionIdentity)
    case duplicateDestinationID(DestinationID)
    case duplicateContributionID(ContributionID)
    case incompatibleAPIVersion(ExtensionIdentity, found: ExtensionAPIVersion)
    case capabilityMismatch(ExtensionIdentity, missing: ExtensionCapability)
}

/// Validates and provides registered extension descriptors.
///
/// Registration fails fast on duplicate ids, incompatible API versions, or
/// capabilities that do not match the supplied contributions.
public final class ExtensionRegistry {
    private var descriptorsByID: [ExtensionIdentity: ExtensionDescriptor] = [:]
    private var extensionByDestinationID: [DestinationID: ExtensionIdentity] = [:]
    private var extensionBySettingsID: [DestinationID: ExtensionIdentity] = [:]
    private var extensionByContributionID: [ContributionID: ExtensionIdentity] = [:]

    public init() {}

    /// Registers a descriptor after validating it.
    public func register(_ descriptor: ExtensionDescriptor) throws {
        guard descriptorsByID[descriptor.id] == nil else {
            throw ExtensionRegistryError.duplicateExtensionID(descriptor.id)
        }

        guard descriptor.apiVersion.isCompatibleWithCurrent else {
            throw ExtensionRegistryError.incompatibleAPIVersion(
                descriptor.id, found: descriptor.apiVersion
            )
        }

        try validateCapabilities(of: descriptor)

        var newDestinationIDs = Set<DestinationID>()
        var newSettingsIDs = Set<DestinationID>()
        var newContributionIDs = Set<ContributionID>()

        for destination in descriptor.openDestinations {
            guard extensionByDestinationID[destination.id] == nil,
                  newDestinationIDs.insert(destination.id).inserted
            else {
                throw ExtensionRegistryError.duplicateDestinationID(destination.id)
            }
        }
        for destination in descriptor.settingsDestinations {
            guard extensionBySettingsID[destination.id] == nil,
                  newSettingsIDs.insert(destination.id).inserted
            else {
                throw ExtensionRegistryError.duplicateDestinationID(destination.id)
            }
        }
        for contribution in descriptor.closedNotchContributions {
            guard extensionByContributionID[contribution.id] == nil,
                  newContributionIDs.insert(contribution.id).inserted
            else {
                throw ExtensionRegistryError.duplicateContributionID(contribution.id)
            }
        }

        descriptorsByID[descriptor.id] = descriptor
        for destination in descriptor.openDestinations {
            extensionByDestinationID[destination.id] = descriptor.id
        }
        for destination in descriptor.settingsDestinations {
            extensionBySettingsID[destination.id] = descriptor.id
        }
        for contribution in descriptor.closedNotchContributions {
            extensionByContributionID[contribution.id] = descriptor.id
        }
    }

    /// All registered descriptors, sorted by identity.
    public var descriptors: [ExtensionDescriptor] {
        descriptorsByID.values.sorted { $0.id < $1.id }
    }

    public func descriptor(for id: ExtensionIdentity) -> ExtensionDescriptor? {
        descriptorsByID[id]
    }

    /// The owning extension for an open destination id.
    public func extensionID(forDestination id: DestinationID) -> ExtensionIdentity? {
        extensionByDestinationID[id]
    }

    /// The owning extension for a settings destination id.
    public func extensionID(forSettingsDestination id: DestinationID) -> ExtensionIdentity? {
        extensionBySettingsID[id]
    }

    /// All open destinations, sorted by order, then title, then id.
    public var openDestinations: [NotchOpenDestination] {
        descriptorsByID.values
            .flatMap(\.openDestinations)
            .sorted(by: Self.openDestinationOrder)
    }

    public func openDestination(for id: DestinationID) -> NotchOpenDestination? {
        openDestinations.first { $0.id == id }
    }

    /// All settings destinations, sorted by title, then id.
    public var settingsDestinations: [ExtensionSettingsDestination] {
        descriptorsByID.values
            .flatMap(\.settingsDestinations)
            .sorted {
                if $0.title != $1.title { return $0.title < $1.title }
                return $0.id < $1.id
            }
    }

    public func settingsDestination(for id: DestinationID) -> ExtensionSettingsDestination? {
        settingsDestinations.first { $0.id == id }
    }

    /// All closed-notch contributions.
    public var closedNotchContributions: [ClosedNotchContribution] {
        descriptorsByID.values.flatMap(\.closedNotchContributions)
    }

    /// Open destinations ordered for tab presentation.
    public static func openDestinationOrder(
        _ lhs: NotchOpenDestination, _ rhs: NotchOpenDestination
    ) -> Bool {
        if lhs.order != rhs.order { return lhs.order < rhs.order }
        if lhs.title != rhs.title { return lhs.title < rhs.title }
        return lhs.id < rhs.id
    }

    private func validateCapabilities(of descriptor: ExtensionDescriptor) throws {
        if !descriptor.openDestinations.isEmpty,
           !descriptor.capabilities.contains(.openDestination)
        {
            throw ExtensionRegistryError.capabilityMismatch(
                descriptor.id, missing: .openDestination
            )
        }
        if !descriptor.closedNotchContributions.isEmpty,
           !descriptor.capabilities.contains(.closedNotchContribution)
        {
            throw ExtensionRegistryError.capabilityMismatch(
                descriptor.id, missing: .closedNotchContribution
            )
        }
        if !descriptor.settingsDestinations.isEmpty,
           !descriptor.capabilities.contains(.settingsDestination)
        {
            throw ExtensionRegistryError.capabilityMismatch(
                descriptor.id, missing: .settingsDestination
            )
        }
    }
}
