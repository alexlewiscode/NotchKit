//
//  ShelfShareProviderTests.swift
//  NotchKitTests
//

import XCTest
@testable import NotchKit

@MainActor
final class ShelfShareProviderTests: XCTestCase {

    @MainActor
    final class ControllableDiscoverer: ShareServiceDiscovering {
        var result: [QuickShareProvider] = []
        var waitForRelease = false
        private(set) var calls = 0
        private var continuation: CheckedContinuation<Void, Never>?

        func discoverProviders() async -> [QuickShareProvider] {
            calls += 1
            if waitForRelease {
                await withCheckedContinuation { self.continuation = $0 }
            }
            return result
        }

        func release() {
            continuation?.resume()
            continuation = nil
        }
    }

    func testLoadPublishesDiscoveredProviders() async {
        let discoverer = ControllableDiscoverer()
        discoverer.result = [
            QuickShareProvider(id: "AirDrop", imageData: nil, supportsRawText: true)
        ]
        let data = ShelfShareProviderDataSource(discoverer: discoverer)

        data.load()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(data.providers.map(\.id), ["AirDrop"])
        XCTAssertTrue(data.didLoad)
        XCTAssertFalse(data.isLoading)
    }

    func testCancellationSuppressesStaleDiscoveryResult() async {
        let discoverer = ControllableDiscoverer()
        discoverer.waitForRelease = true
        discoverer.result = [
            QuickShareProvider(id: "AirDrop", imageData: nil, supportsRawText: true)
        ]
        let data = ShelfShareProviderDataSource(discoverer: discoverer)

        data.load()
        while discoverer.calls < 1 { await Task.yield() }

        // The page closes before discovery completes.
        data.cancel()
        discoverer.release()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(data.providers.isEmpty, "A cancelled discovery must not publish")
        XCTAssertFalse(data.didLoad)
    }

    func testSelectedProviderRemainsSelectableBeforeDiscovery() {
        let data = ShelfShareProviderDataSource(discoverer: ControllableDiscoverer())
        let providers = data.providersIncludingSelected(id: "System Share Menu")
        XCTAssertEqual(providers.map(\.id), ["System Share Menu"])
    }
}
