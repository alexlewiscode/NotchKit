//
//  TestHostPolicy.swift
//  NotchKit
//
//  The one place that decides whether this process is an app-hosted test host.
//
//  App-hosted unit tests run inside the real application: `main.swift` runs,
//  SwiftUI builds the scene, and the delegate is constructed. Without a policy,
//  production startup (identity migration, extension bootstrap, service
//  singletons, observers, and real storage) would run during tests.
//
//  The policy is evaluated once, as early as `main.swift`, and every production
//  side effect must consult it. It never changes the normal launch path.
//

import Foundation

enum TestHostPolicy {
    /// True when the current process is hosting an XCTest bundle.
    ///
    /// `XCTestConfigurationFilePath` and friends are set by the XCTest harness for
    /// app-hosted tests. `NOTCHKIT_TEST_HOST` is set explicitly by the committed
    /// test scheme so the policy does not depend on a private harness detail
    /// alone. `XCTestCase` is loaded into the host process as a final fallback.
    nonisolated static let isActive: Bool = detectTestHost()

    /// Isolated, process-scoped root for any on-disk artifacts produced while
    /// running as a test host. Production storage is never used.
    nonisolated static let isolationRoot: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("notchkit-test-host", isDirectory: true)
        .appendingPathComponent(String(ProcessInfo.processInfo.processIdentifier), isDirectory: true)

    /// Records that the production launch path ran. Tests assert it stays false so
    /// a guard regression cannot silently reintroduce production startup.
    nonisolated(unsafe) private(set) static var productionStartupDidRun = false

    /// Creates the isolated storage root. Called from `main.swift` before any code
    /// that could touch disk.
    nonisolated static func activateIfNeeded() {
        guard isActive else { return }
        try? FileManager.default.createDirectory(
            at: isolationRoot,
            withIntermediateDirectories: true
        )
    }

    /// Marks that production startup ran. A no-op under the test host.
    nonisolated static func markProductionStartup() {
        guard !isActive else { return }
        productionStartupDidRun = true
    }

    private nonisolated static func detectTestHost() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["NOTCHKIT_TEST_HOST"] == "1" { return true }
        if environment["XCTestConfigurationFilePath"] != nil { return true }
        if environment["XCTestBundlePath"] != nil { return true }
        if environment["XCTestSessionIdentifier"] != nil { return true }
        return NSClassFromString("XCTestCase") != nil
    }
}
