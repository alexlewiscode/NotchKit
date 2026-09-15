//
//  main.swift
//  NotchKit
//
//  Explicit entry point so the one-time identity migration runs before SwiftUI
//  resolves persisted settings such as @Default and @AppStorage.
//

import Foundation

// Determine the launch mode before any production side effect. Under an
// app-hosted test bundle the migration, bootstrap, and service startup must not
// run (see TestHostPolicy).
TestHostPolicy.activateIfNeeded()

if !TestHostPolicy.isActive {
    TestHostPolicy.markProductionStartup()
    IdentityMigrationCoordinator.runBlockingIfNeeded()
}

NotchKitApp.main()