//
//  ExtensionHost.swift
//  NotchExtensionRuntime
//
//  The extension lifecycle coordinator: enable, start, stop, disable, failure,
//  and removal.
//

import Foundation
import NotchExtensionSDK

/// Drives the runtime lifecycle of registered extensions.
///
/// The host is app-wide and `@MainActor`. It reconciles the desired enabled
/// state (owned by `ExtensionManager`) against live instances:
///
/// - enable / start: create the instance, `activate()`, then publish its
///   contributions;
/// - disable / stop: remove contributions, `deactivate()`, then cancel every
///   registered teardown;
/// - failure: tear the instance down and record `.failed`;
/// - removal: stop and deregister.
///
/// Repeated and rapid enable/disable calls are coalesced with a per-extension
/// generation counter, so at most one service instance exists and stale
/// completion callbacks are ignored.
@MainActor
public final class ExtensionHost {
    /// Builds the context (host services + teardown scope) for an activation.
    public typealias ContextFactory = @MainActor (ExtensionIdentity, ExtensionCancellationBag) -> ExtensionContext

    private let registry: ExtensionRegistry
    private let manager: ExtensionManager
    /// Live contributions of active extensions.
    public let contributions: ContributionStore
    private let makeContext: ContextFactory

    private var states: [ExtensionIdentity: ExtensionRuntimeState] = [:]
    private var instances: [ExtensionIdentity: any NotchExtension] = [:]
    private var bags: [ExtensionIdentity: ExtensionCancellationBag] = [:]
    private var generations: [ExtensionIdentity: Int] = [:]
    private var tasks: [ExtensionIdentity: Task<Void, Never>] = [:]
    /// Monotonic across the whole host, never reset, so a stale completion can
    /// never match a newer lifecycle even after `remove` or `shutdown`.
    private var nextGeneration = 0

    /// Called whenever any extension's phase changes.
    public var onStateChanged: (@MainActor () -> Void)?

    public init(
        registry: ExtensionRegistry,
        manager: ExtensionManager,
        contributions: ContributionStore = ContributionStore(),
        makeContext: @escaping ContextFactory
    ) {
        self.registry = registry
        self.manager = manager
        self.contributions = contributions
        self.makeContext = makeContext
    }

    /// Wires enabled-state observation, applies defaults, and activates enabled
    /// extensions.
    public func start() {
        manager.onEnabledChanged = { [weak self] id, enabled in
            self?.enabledStateChanged(id, enabled: enabled)
        }
        manager.reconcile()
        reconcileNow()
    }

    /// The current phase for an extension.
    public func phase(for id: ExtensionIdentity) -> ExtensionRuntimePhase {
        states[id]?.phase ?? .inactive
    }

    /// The current state for an extension.
    public func state(for id: ExtensionIdentity) -> ExtensionRuntimeState {
        states[id] ?? ExtensionRuntimeState(id: id, phase: .inactive)
    }

    /// All non-inactive states, sorted by identity.
    public var activeStates: [ExtensionRuntimeState] {
        states.values
            .filter { $0.phase != .inactive }
            .sorted { $0.id < $1.id }
    }

    /// Enables or disables an extension and reconciles.
    public func setEnabled(_ enabled: Bool, for id: ExtensionIdentity) {
        // `ExtensionManager` fires `onEnabledChanged` only when the value
        // actually changes, and that callback reconciles. Calling reconcile
        // here as well would schedule a second, overlapping transition.
        manager.setEnabled(enabled, for: id)
    }

    /// Retries a failed or permission-blocked activation for an extension whose
    /// desired state is still enabled. This is the explicit, user-initiated
    /// path; `reconcileNow()` deliberately does not auto-retry permission gates.
    public func retry(_ id: ExtensionIdentity) {
        switch phase(for: id) {
        case .failed, .requiresPermission:
            clearInstance(id)
            setPhase(.inactive, id)
        case .inactive, .activating, .active, .deactivating:
            break
        }
        reconcileNow()
    }

    /// Reconciles desired enabled state against live instances.
    public func reconcileNow() {
        for definition in registry.definitions {
            let id = definition.id
            let enabled = manager.isEnabled(id)
            let phase = phase(for: id)

            if enabled {
                switch phase {
                case .inactive, .failed, .deactivating:
                    beginActivation(definition)
                case .activating, .active:
                    break
                case .requiresPermission:
                    // The desired state is enabled but a permission gate is
                    // unmet. Retrying automatically would re-prompt on every
                    // reconcile; the user retries explicitly (`retry(_:)`).
                    break
                }
            } else {
                switch phase {
                case .active, .activating, .deactivating:
                    beginDeactivation(id)
                case .failed, .requiresPermission:
                    clearInstance(id)
                    setPhase(.inactive, id)
                case .inactive:
                    break
                }
            }
        }
    }

    /// Stops and removes an extension.
    public func remove(_ id: ExtensionIdentity) {
        stopNow(id)
        registry.remove(id)
        manager.setEnabled(false, for: id)
        contributions.removeContributions(for: id)
        instances.removeValue(forKey: id)
        bags.removeValue(forKey: id)
        states.removeValue(forKey: id)
        tasks[id]?.cancel()
        tasks.removeValue(forKey: id)
        generations.removeValue(forKey: id)
        onStateChanged?()
    }

    /// Stops every extension and clears all runtime state.
    public func shutdown() {
        for id in Set(instances.keys).union(states.keys) {
            stopNow(id)
        }
        contributions.removeAll()
        instances.removeAll()
        bags.removeAll()
        states.removeAll()
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        generations.removeAll()
        onStateChanged?()
    }

    /// Awaits pending activation/deactivation work. Intended for tests.
    public func waitForQuiescence() async {
        var guardCounter = 0
        while !tasks.isEmpty, guardCounter < 64 {
            guardCounter += 1
            let pending = Array(tasks.values)
            for task in pending {
                _ = await task.value
            }
        }
    }

    // MARK: - Lifecycle

    private func enabledStateChanged(_ id: ExtensionIdentity, enabled: Bool) {
        reconcileNow()
    }

    private func beginActivation(_ definition: ExtensionDefinition) {
        let id = definition.id
        // A newer transition supersedes any pending activation or deactivation
        // for this identity. Cancelling the task is not enough on its own: the
        // task may already be queued, so teardown must also be generation-guarded
        // (see `beginDeactivation`).
        tasks[id]?.cancel()
        tasks[id] = nil
        advanceGeneration(for: id)
        let generation = generations[id] ?? 0

        // Tear down the previous instance exactly once, here and now, under the
        // new generation. This transfers teardown ownership to the activation so
        // a superseded deactivation task cannot stop the shared service again.
        instances[id]?.deactivate()
        bags[id]?.cancelAll()
        instances.removeValue(forKey: id)
        bags.removeValue(forKey: id)

        setPhase(.activating, id)

        let bag = ExtensionCancellationBag()
        bags[id] = bag
        let context = makeContext(id, bag)
        let instance = definition.makeInstance(context)
        instances[id] = instance

        tasks[id] = Task { [weak self] in
            do {
                try await instance.activate()
                self?.finishActivation(id, generation: generation, instance: instance)
            } catch {
                self?.failActivation(id, generation: generation, instance: instance, error: error)
            }
        }
    }

    private func finishActivation(
        _ id: ExtensionIdentity,
        generation: Int,
        instance: any NotchExtension
    ) {
        guard generations[id] == generation, instances[id] === instance else {
            tearDownSupersededActivation(instance, id: id)
            return
        }
        guard let instance = instances[id] else {
            tasks[id] = nil
            return
        }

        guard manager.isEnabled(id) else {
            // Disabled while activating: coalesce straight to deactivation.
            beginDeactivation(id)
            return
        }

        do {
            // Settings are declared on `ExtensionDefinition.settings` and served
            // by the host settings catalog, so the lifecycle no longer publishes
            // instance settings destinations. The empty array keeps the
            // `ContributionStore` API (and its duplicate-id checks) unchanged.
            try contributions.set(
                open: instance.openDestinations(),
                closed: instance.closedNotchContributions(),
                settings: [],
                for: id
            )
        } catch {
            failActivation(id, generation: generation, instance: instance, error: error)
            return
        }

        tasks[id] = nil
        setPhase(.active, id)
    }

    private func failActivation(
        _ id: ExtensionIdentity,
        generation: Int,
        instance: any NotchExtension,
        error: Error
    ) {
        guard generations[id] == generation, instances[id] === instance else {
            tearDownSupersededActivation(instance, id: id)
            return
        }
        instance.deactivate()
        bags[id]?.cancelAll()
        clearInstance(id)
        contributions.removeContributions(for: id)
        tasks[id] = nil
        setPhase(Self.phase(for: error), id)
    }

    /// Maps an activation error to an honest runtime phase. A permission gate is
    /// not a failure: the desired state stays enabled and the user can grant the
    /// permission and retry.
    private static func phase(for error: Error) -> ExtensionRuntimePhase {
        switch error {
        case ExtensionActivationError.permissionRequired(let permission):
            return .requiresPermission("\(permission.rawValue) permission required")
        case ExtensionActivationError.deviceUnavailable(let reason):
            return .failed(reason)
        default:
            return .failed(String(describing: error))
        }
    }

    /// Undoes a late activation that a newer lifecycle superseded.
    ///
    /// A superseded `activate()` can resume after the host already moved on and
    /// start a shared service. If a newer instance currently owns that service
    /// (the extension is still enabled and has a live instance), touching it
    /// would risk stopping the current owner, so the host leaves it alone.
    /// Otherwise — the extension was disabled or removed, the superseding
    /// activation failed, or the host shut down — nothing owns the service and
    /// the late side effects must be cleaned up.
    private func tearDownSupersededActivation(_ instance: any NotchExtension, id: ExtensionIdentity) {
        if manager.isEnabled(id), instances[id] != nil { return }
        instance.deactivate()
    }

    private func beginDeactivation(_ id: ExtensionIdentity) {
        advanceGeneration(for: id)
        let generation = generations[id] ?? 0

        setPhase(.deactivating, id)
        contributions.removeContributions(for: id)

        tasks[id]?.cancel()
        let instance = instances[id]
        let bag = bags[id]

        tasks[id] = Task { [weak self] in
            guard let self else { return }
            // If a newer transition superseded this deactivation, it owns
            // teardown. Checking the generation *before* tearing down is what
            // prevents a stale deactivation from stopping a service that a newer
            // activation already started. (The body runs synchronously on the
            // main actor, so the generation cannot change mid-teardown.)
            guard self.generations[id] == generation else { return }
            instance?.deactivate()
            bag?.cancelAll()
            self.clearInstance(id)
            self.tasks[id] = nil
            self.setPhase(.inactive, id)
        }
    }

    /// Synchronous best-effort stop used by `remove` and `shutdown`.
    private func stopNow(_ id: ExtensionIdentity) {
        advanceGeneration(for: id)
        contributions.removeContributions(for: id)
        instances[id]?.deactivate()
        bags[id]?.cancelAll()
        tasks[id]?.cancel()
        tasks[id] = nil
    }

    private func clearInstance(_ id: ExtensionIdentity) {
        instances.removeValue(forKey: id)
        bags.removeValue(forKey: id)
    }

    private func advanceGeneration(for id: ExtensionIdentity) {
        nextGeneration += 1
        generations[id] = nextGeneration
    }

    private func setPhase(_ phase: ExtensionRuntimePhase, _ id: ExtensionIdentity) {
        states[id] = ExtensionRuntimeState(id: id, phase: phase)
        onStateChanged?()
    }
}