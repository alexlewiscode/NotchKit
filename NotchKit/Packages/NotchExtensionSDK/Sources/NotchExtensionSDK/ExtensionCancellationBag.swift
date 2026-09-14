//
//  ExtensionCancellationBag.swift
//  NotchExtensionSDK
//
//  Owns everything an activated extension must tear down.
//

import Foundation

/// Collects extension-owned cancellables and teardown closures so that
/// deactivation is complete and idempotent.
///
/// An extension registers tasks, timers, notification observers, or any custom
/// teardown block. `cancelAll()` runs every teardown exactly once. Registering
/// after cancellation runs the teardown immediately, so a late callback cannot
/// leave a live resource behind.
@MainActor
public final class ExtensionCancellationBag {
    private var teardowns: [() -> Void] = []
    private var cancelled = false

    public init() {}

    /// Whether `cancelAll()` has run.
    public var isCancelled: Bool { cancelled }

    /// Registers a teardown block.
    public func add(_ teardown: @escaping () -> Void) {
        if cancelled {
            teardown()
            return
        }
        teardowns.append(teardown)
    }

    /// Registers a task to be cancelled.
    public func add(_ task: Task<Void, Never>) {
        add { task.cancel() }
    }

    /// Registers a timer to be invalidated.
    public func add(_ timer: Timer) {
        add { timer.invalidate() }
    }

    /// Registers a notification observer token for removal.
    public func add(observer token: Any, center: NotificationCenter = .default) {
        add { center.removeObserver(token) }
    }

    /// Runs every registered teardown once, in reverse registration order.
    public func cancelAll() {
        guard !cancelled else { return }
        cancelled = true
        let pending = teardowns
        teardowns.removeAll()
        for teardown in pending.reversed() {
            teardown()
        }
    }
}
