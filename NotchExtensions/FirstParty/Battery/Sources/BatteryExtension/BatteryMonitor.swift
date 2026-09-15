//
//  BatteryMonitor.swift
//  BatteryExtension
//
//  The app-wide battery service. One observer, shared by every consumer.
//

import Combine
import Foundation

/// App-wide battery state.
///
/// Exactly one `start()` is active at a time regardless of how many consumers
/// observe it. The extension activates and deactivates it; host views only
/// observe the published value, so adding a display never starts another
/// observer.
@MainActor
public final class BatteryMonitor: ObservableObject {
    /// The most recent reading. Published so SwiftUI consumers update.
    @Published public private(set) var snapshot: BatterySnapshot
    /// Whether the underlying source is currently observing.
    @Published public private(set) var isRunning = false

    /// Called after `snapshot` updates. Used by the extension to request
    /// presentation; never used to start or stop the service.
    public var onChange: (@MainActor (BatterySnapshot) -> Void)?

    private let source: PowerSourceObserving
    /// Monotonic per-start token so a late callback from a previous start is
    /// ignored after `stop()`.
    private var generation = 0

    public init(source: PowerSourceObserving? = nil) {
        // Do not read power state at construction: metadata/registration must
        // not touch the system, and the extension is not active yet.
        self.source = source ?? IOKitPowerSource()
        self.snapshot = .unknown
    }

    /// Starts observing if not already running. Idempotent.
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        generation += 1
        let generation = self.generation
        source.start { [weak self] newValue in
            guard let self, self.isRunning, self.generation == generation else {
                return
            }
            self.snapshot = newValue
            self.onChange?(newValue)
        }
        // Push the current reading immediately so a consumer never shows a
        // stale first frame.
        snapshot = source.current
    }

    /// Stops observing. Idempotent and safe after a partial start.
    public func stop() {
        guard isRunning else { return }
        isRunning = false
        generation += 1
        source.stop()
    }

    /// Whether the source is observing. Exposed for lifecycle tests.
    var isSourceRunning: Bool { isRunning }
}