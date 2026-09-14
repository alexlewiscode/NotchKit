//
//  NotchKitIdentity.swift
//  NotchExtensionSDK
//
//  Canonical NotchKit identifier namespace. The legacy constants are read-only
//  and exist so the one-time identity migration can find pre-NotchKit data.
//

import Foundation

/// Canonical identifiers for the NotchKit app identity.
///
/// Persisted namespaces (bundle identifier, defaults keys, storage directory)
/// are stable and must only change with a tested migration.
public enum NotchKitIdentity {
    /// Current app bundle identifier. Defines the UserDefaults domain and the
    /// sandbox container.
    public static let bundleIdentifier = "com.notchkit.app"

    /// Current XPC helper bundle identifier. Also the Mach service name.
    public static let xpcServiceName = "com.notchkit.app.XPCHelper"

    /// Current UserDefaults key for persisted extension enabled state.
    public static let extensionStateDefaultsKey = "com.notchkit.extensions.state"

    /// Current Application Support directory name for Shelf data.
    public static let shelfDirectoryName = "NotchKit"

    /// Prefix shared by extension identities, destination ids, and
    /// contribution ids.
    public static let identifierPrefix = "com.notchkit."

    /// Identifiers used by the pre-NotchKit (boringNotch) build. Read-only:
    /// consumed by the one-time migration and never written.
    public enum Legacy {
        /// Previous app bundle identifier.
        public static let bundleIdentifier = "theboringteam.boringnotch"
        /// Previous XPC helper bundle identifier / Mach service name.
        public static let xpcServiceName = "theboringteam.boringnotch.BoringNotchXPCHelper"
        /// Previous UserDefaults key for persisted extension state.
        public static let extensionStateDefaultsKey = "com.boringnotch.extensions.state"
        /// Previous Application Support directory name for Shelf data.
        public static let shelfDirectoryName = "boringNotch"
        /// Previous prefix shared by extension ids.
        public static let identifierPrefix = "com.boringnotch."
    }
}