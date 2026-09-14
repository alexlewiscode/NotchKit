//
//  ExtensionEntryPoint.swift
//  NotchExtensionSDK
//
//  Declares where an extension attaches to the host. Entry points are metadata
//  only; the content behind them is produced by an activated instance.
//

import Foundation

/// The kind of host feature an extension entry point binds to.
public enum ExtensionEntryPointKind: String, Codable, CaseIterable, Sendable {
    /// An open-notch destination (tab).
    case openDestination = "open-destination"
    /// A closed-notch contribution.
    case closedNotchContribution = "closed-notch-contribution"
    /// A settings page reachable from the Extensions hub.
    case settingsDestination = "settings-destination"

    /// The capability that must be declared for this entry point kind.
    public var requiredCapability: ExtensionCapability {
        ExtensionCapability(rawValue: rawValue)
    }
}

/// A declared attachment point. The `id` is the stable identity used for
/// routing, recency, and tie-breaking; it is distinct from the extension id.
///
/// For out-of-process extensions, `sceneName` names the remote scene the host
/// should request. It is unused for `.compiledIn` extensions.
public struct ExtensionEntryPoint: Hashable, Codable, Identifiable, Sendable {
    /// Stable identity of the contributed destination or contribution.
    public let id: String
    /// What the entry point binds to.
    public let kind: ExtensionEntryPointKind
    /// Remote scene name, for future out-of-process presentation. Reserved.
    public let sceneName: String?
    /// Optional free-form metadata carried through the manifest unchanged.
    public let metadata: [String: String]

    public init(
        id: String,
        kind: ExtensionEntryPointKind,
        sceneName: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.sceneName = sceneName
        self.metadata = metadata
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, sceneName, metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.kind = try container.decode(ExtensionEntryPointKind.self, forKey: .kind)
        self.sceneName = try container.decodeIfPresent(String.self, forKey: .sceneName)
        self.metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(sceneName, forKey: .sceneName)
        if !metadata.isEmpty {
            try container.encode(metadata, forKey: .metadata)
        }
    }
}
