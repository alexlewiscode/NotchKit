//
//  BatterySettings.swift
//  BatteryExtension
//
//  Battery settings, stored under the same UserDefaults keys the host has
//  always used so existing preferences are preserved across extraction.
//

import Foundation

/// The battery settings keys.
///
/// These raw strings are intentionally identical to the historical host keys in
/// `Constants.swift`. Reusing them preserves every user's existing preference
/// and lets both the host settings pane and the extension settings page agree.
public enum BatterySettingsKeys {
    public static let showPowerStatusNotifications = "showPowerStatusNotifications"
    public static let showBatteryIndicator = "showBatteryIndicator"
    public static let showBatteryPercentage = "showBatteryPercentage"
    public static let showPowerStatusIcons = "showPowerStatusIcons"
}

/// Read/write access to Battery settings.
public enum BatterySettings {
    /// Whether power-status notifications are shown when the notch is closed.
    public static var showPowerStatusNotifications: Bool {
        get { bool(BatterySettingsKeys.showPowerStatusNotifications) }
        set { set(newValue, BatterySettingsKeys.showPowerStatusNotifications) }
    }

    /// Whether the battery indicator is shown in the open-notch header.
    public static var showBatteryIndicator: Bool {
        get { bool(BatterySettingsKeys.showBatteryIndicator) }
        set { set(newValue, BatterySettingsKeys.showBatteryIndicator) }
    }

    /// Whether the numeric battery percentage is shown.
    public static var showBatteryPercentage: Bool {
        get { bool(BatterySettingsKeys.showBatteryPercentage) }
        set { set(newValue, BatterySettingsKeys.showBatteryPercentage) }
    }

    /// Whether charging/plug icons are shown.
    public static var showPowerStatusIcons: Bool {
        get { bool(BatterySettingsKeys.showPowerStatusIcons) }
        set { set(newValue, BatterySettingsKeys.showPowerStatusIcons) }
    }

    private static func bool(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    private static func set(_ value: Bool, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}