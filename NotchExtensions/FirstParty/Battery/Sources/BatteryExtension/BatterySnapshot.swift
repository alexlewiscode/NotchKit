//
//  BatterySnapshot.swift
//  BatteryExtension
//
//  Immutable, runtime-free battery state.
//

import Foundation

/// A point-in-time battery/power reading.
///
/// Deliberately free of IOKit and AppKit types so it can cross the extension
/// boundary and be constructed by tests.
public struct BatterySnapshot: Equatable, Sendable {
    /// Whether an external power source is connected.
    public var isPluggedIn: Bool
    /// Whether the battery is actively charging.
    public var isCharging: Bool
    /// Current charge percentage (`0...100`).
    public var currentCapacity: Float
    /// Maximum charge percentage (`0...100`).
    public var maxCapacity: Float
    /// Whether macOS Low Power Mode is enabled.
    public var isInLowPowerMode: Bool
    /// Minutes until fully charged, or `0` when unknown.
    public var timeToFullChargeMinutes: Int

    public init(
        isPluggedIn: Bool,
        isCharging: Bool,
        currentCapacity: Float,
        maxCapacity: Float,
        isInLowPowerMode: Bool,
        timeToFullChargeMinutes: Int
    ) {
        self.isPluggedIn = isPluggedIn
        self.isCharging = isCharging
        self.currentCapacity = currentCapacity
        self.maxCapacity = maxCapacity
        self.isInLowPowerMode = isInLowPowerMode
        self.timeToFullChargeMinutes = timeToFullChargeMinutes
    }

    /// A neutral reading used before the first real sample and on read failure.
    public static let unknown = BatterySnapshot(
        isPluggedIn: false,
        isCharging: false,
        currentCapacity: 0,
        maxCapacity: 0,
        isInLowPowerMode: false,
        timeToFullChargeMinutes: 0
    )
}