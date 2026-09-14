//
//  ExtensionDescriptor.swift
//  NotchAPI
//
//  The declarative description of a first-party extension.
//

import Foundation

/// The origin of an extension.
public enum ExtensionSource: String, Hashable {
    /// An extension compiled into the app.
    case firstParty
}

/// The complete declaration of a NotchKit extension.
///
/// Descriptors are validated by `ExtensionRegistry` and reconciled by
/// `ExtensionManager`. They describe what an extension contributes; they never
/// grant access to the notch window, geometry, monitors, or permissions.
public struct ExtensionDescriptor: Identifiable {
    /// Stable reverse-DNS identity.
    public let id: ExtensionIdentity
    /// User-visible name.
    public let displayName: String
    /// Optional short description.
    public let summary: String?
    /// SF Symbol used to represent the extension.
    public let iconSystemName: String
    /// The API version the extension targets.
    public let apiVersion: ExtensionAPIVersion
    /// The origin of the extension.
    public let source: ExtensionSource
    /// The kinds of contributions this extension provides.
    public let capabilities: Set<ExtensionCapability>
    /// Whether the extension is enabled on first run.
    public let defaultEnabled: Bool
    /// Open-notch destinations contributed by the extension.
    public let openDestinations: [NotchOpenDestination]
    /// Closed-notch contributions provided by the extension.
    public let closedNotchContributions: [ClosedNotchContribution]
    /// Settings destinations contributed by the extension.
    public let settingsDestinations: [ExtensionSettingsDestination]

    public init(
        id: ExtensionIdentity,
        displayName: String,
        summary: String? = nil,
        iconSystemName: String,
        apiVersion: ExtensionAPIVersion = .current,
        source: ExtensionSource = .firstParty,
        capabilities: Set<ExtensionCapability>,
        defaultEnabled: Bool,
        openDestinations: [NotchOpenDestination] = [],
        closedNotchContributions: [ClosedNotchContribution] = [],
        settingsDestinations: [ExtensionSettingsDestination] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.summary = summary
        self.iconSystemName = iconSystemName
        self.apiVersion = apiVersion
        self.source = source
        self.capabilities = capabilities
        self.defaultEnabled = defaultEnabled
        self.openDestinations = openDestinations
        self.closedNotchContributions = closedNotchContributions
        self.settingsDestinations = settingsDestinations
    }
}
