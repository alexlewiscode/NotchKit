//
//  PowerSourceObserving.swift
//  BatteryExtension
//
//  The power-source seam: a mockable protocol plus the IOKit-backed observer.
//
//  Battery owns this system read-only observation itself. It is not a
//  privileged host resource, and core keeps ownership of geometry, windowing,
//  and presentation only.
//

import Foundation
import IOKit.ps

/// A source of battery/power readings that can be observed.
///
/// The protocol exists so lifecycle tests can drive deterministic events without
/// touching real hardware.
@MainActor
public protocol PowerSourceObserving: AnyObject {
    /// The most recent reading.
    var current: BatterySnapshot { get }

    /// Begins observing. Implementations must be safe to call repeatedly, but
    /// `BatteryMonitor` already guards against duplicate starts.
    func start(onChange: @escaping @MainActor (BatterySnapshot) -> Void)

    /// Stops observing and releases every OS-level resource exactly once.
    func stop()
}

/// IOKit-backed power source observer.
///
/// Owns exactly one `IOPSNotificationCreateRunLoopSource` and one
/// `NSProcessInfoPowerStateDidChange` observer, both installed on the main run
/// loop and both removed by `stop()`.
@MainActor
public final class IOKitPowerSource: PowerSourceObserving {
    private var runLoopSource: CFRunLoopSource?
    private var lowPowerObserver: NSObjectProtocol?
    private var onChange: (@MainActor (BatterySnapshot) -> Void)?
    private var isRunning = false

    public init() {}

    public var current: BatterySnapshot {
        Self.readSnapshot()
    }

    public func start(onChange: @escaping @MainActor (BatterySnapshot) -> Void) {
        guard !isRunning else { return }
        isRunning = true
        self.onChange = onChange

        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { rawContext in
            guard let rawContext else { return }
            let source = Unmanaged<IOKitPowerSource>.fromOpaque(rawContext).takeUnretainedValue()
            // The source is installed on the main run loop, so this callback
            // runs on the main thread.
            MainActor.assumeIsolated {
                source.emit()
            }
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }

        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.emit()
            }
        }
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
            self.runLoopSource = nil
        }
        if let lowPowerObserver {
            NotificationCenter.default.removeObserver(lowPowerObserver)
            self.lowPowerObserver = nil
        }
        onChange = nil
    }

    private func emit() {
        onChange?(Self.readSnapshot())
    }

    /// Reads the current power source description. Returns `.unknown` on any
    /// failure rather than throwing, matching the previous behaviour.
    static func readSnapshot() -> BatterySnapshot {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(snapshot, source)?
                  .takeUnretainedValue() as? [String: Any]
        else {
            return .unknown
        }

        let currentCapacity = description[kIOPSCurrentCapacityKey] as? Float ?? 0
        let maxCapacity = description[kIOPSMaxCapacityKey] as? Float ?? 0
        let isCharging = description["Is Charging"] as? Bool ?? false
        let powerSource = description[kIOPSPowerSourceStateKey] as? String
        let timeToFull = description[kIOPSTimeToFullChargeKey] as? Int ?? 0

        return BatterySnapshot(
            isPluggedIn: powerSource == kIOPSACPowerValue,
            isCharging: isCharging,
            currentCapacity: currentCapacity,
            maxCapacity: maxCapacity,
            isInLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            timeToFullChargeMinutes: timeToFull
        )
    }
}