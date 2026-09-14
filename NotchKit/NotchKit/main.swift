//
//  main.swift
//  NotchKit
//
//  Explicit entry point so the one-time identity migration runs before SwiftUI
//  resolves persisted settings such as @Default and @AppStorage.
//

import Foundation

IdentityMigrationCoordinator.runBlockingIfNeeded()

NotchKitApp.main()