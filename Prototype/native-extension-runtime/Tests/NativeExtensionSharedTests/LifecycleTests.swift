import XCTest
@testable import NativeExtensionShared

final class LifecycleTests: XCTestCase {
    func testHappyPathActivatesAndDeactivates() throws {
        var lifecycle = NativeExtensionLifecycle()
        try lifecycle.apply(.activate)
        XCTAssertEqual(lifecycle.phase, .activating)
        try lifecycle.apply(.didActivate)
        XCTAssertEqual(lifecycle.phase, .active)
        try lifecycle.apply(.deactivate)
        XCTAssertEqual(lifecycle.phase, .inactive)
    }

    func testInterruptionCanReconnectThroughFreshActivation() throws {
        var lifecycle = NativeExtensionLifecycle(phase: .active)
        try lifecycle.apply(.interrupted)
        XCTAssertEqual(lifecycle.phase, .interrupted)
        try lifecycle.apply(.activate)
        XCTAssertEqual(lifecycle.phase, .activating)
        try lifecycle.apply(.didActivate)
        XCTAssertEqual(lifecycle.phase, .active)
    }

    func testDuplicateDidActivateIsRejected() throws {
        var lifecycle = NativeExtensionLifecycle(phase: .active)
        XCTAssertThrowsError(try lifecycle.apply(.didActivate))
        XCTAssertEqual(lifecycle.phase, .active)
    }

    func testSystemDisableWinsFromAnyLivePhase() throws {
        var lifecycle = NativeExtensionLifecycle(phase: .active)
        try lifecycle.apply(.systemDisabled)
        XCTAssertEqual(lifecycle.phase, .disabled)
    }
}
