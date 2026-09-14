//
//  ContractTestDoubles.swift
//  NotchExtensionRuntimeTests
//
//  Host-service test doubles for the SDK contract. Not shipped.
//

import Foundation
import NotchExtensionSDK
import SwiftUI

@MainActor
final class TestPresentationService: NotchPresentationService {
    struct Call: Equatable {
        let request: PresentationRequest
        let target: PresentationTarget
    }

    var availableDisplays: [DisplayID] = []
    private(set) var calls: [Call] = []

    func request(_ request: PresentationRequest, target: PresentationTarget) {
        calls.append(Call(request: request, target: target))
    }
}

final class TestScopedStore: ExtensionScopedStore {
    let schemaVersion = 1
    private(set) var values: [String: Data] = [:]

    func data(forKey key: String) -> Data? { values[key] }
    func set(_ data: Data?, forKey key: String) {
        if let data { values[key] = data } else { values.removeValue(forKey: key) }
    }
}

@MainActor
final class TestPermissionService: NotchPermissionService {
    var statuses: [NotchPermission: NotchPermissionStatus] = [:]

    func status(for permission: NotchPermission) -> NotchPermissionStatus {
        statuses[permission] ?? .notDetermined
    }

    func request(_ permission: NotchPermission) async -> NotchPermissionStatus {
        statuses[permission] ?? .notDetermined
    }
}

/// A configurable in-process extension used to exercise the lifecycle.
@MainActor
final class TestLifecycleExtension: NotchExtension {
    var failOnActivate = false
    var activateDelay: Duration = .zero

    private(set) var activateCount = 0
    private(set) var deactivateCount = 0
    private(set) var isActive = false
    private(set) var teardownRan = false
    var lastContext: ExtensionContext?

    func activate() async throws {
        activateCount += 1
        if activateDelay > .zero {
            try? await Task.sleep(for: activateDelay)
        }
        if failOnActivate {
            throw TestError.activationFailed
        }
        isActive = true
        lastContext?.cancellation.add { [weak self] in
            self?.teardownRan = true
        }
    }

    func deactivate() {
        deactivateCount += 1
        isActive = false
        lastContext?.cancellation.cancelAll()
    }

    func openDestinations() -> [NotchOpenDestination] {
        guard isActive else { return [] }
        return [
            NotchOpenDestination(
                id: DestinationID("com.notchkit.test.page"),
                title: "Test",
                iconSystemName: "gear",
                order: 50,
                isAvailable: { true },
                makeView: { AnyView(EmptyView()) }
            )
        ]
    }

    enum TestError: Error { case activationFailed }
}

/// An extension whose contributions are fixed at construction.
@MainActor
final class StaticExtension: NotchExtension {
    private let open: [NotchOpenDestination]
    private let closed: [ClosedNotchContribution]
    private let settings: [ExtensionSettingsDestination]
    private(set) var activateCount = 0
    private(set) var deactivateCount = 0
    private(set) var isActive = false

    init(
        open: [NotchOpenDestination] = [],
        closed: [ClosedNotchContribution] = [],
        settings: [ExtensionSettingsDestination] = []
    ) {
        self.open = open
        self.closed = closed
        self.settings = settings
    }

    func activate() async throws {
        activateCount += 1
        isActive = true
    }

    func deactivate() {
        deactivateCount += 1
        isActive = false
    }

    func openDestinations() -> [NotchOpenDestination] { open }
    func closedNotchContributions() -> [ClosedNotchContribution] { closed }
    func settingsDestinations() -> [ExtensionSettingsDestination] { settings }
}
