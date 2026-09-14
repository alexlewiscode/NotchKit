//
//  HelloExtension.swift
//  NotchExtensions example
//
//  Reference implementation of a compiled-in first-party extension against the
//  NotchExtensionSDK lifecycle contract.
//
//  This file is illustrative source, not part of the app target. The same
//  shape is compiled and exercised by the package tests
//  (ExampleExtensionContractTests) so the contract cannot drift from its
//  example.
//
//  It demonstrates:
//  - metadata-only manifest separate from the runtime instance;
//  - activation that starts work and registers it with the cancellation bag;
//  - deactivation that tears that work down;
//  - contributions produced only while active.
//

import Foundation
import NotchExtensionSDK
import SwiftUI

/// Runtime-free manifest for the example. Matches manifest.json.
enum HelloExtensionManifest {
    static func metadata() throws -> ExtensionMetadata {
        ExtensionMetadata(
            id: try ExtensionIdentity("com.notchkit.example.hello"),
            displayName: "Hello Extension",
            summary: "Reference example: a compiled-in first-party extension with one open destination.",
            iconSystemName: "hand.wave",
            extensionVersion: ExtensionVersion(major: 1, minor: 0, patch: 0),
            apiVersion: ExtensionAPIVersion(major: 1, minor: 0, patch: 0),
            supportedHostVersions: ExtensionVersionRange(minimum: ExtensionVersion(major: 1, minor: 0, patch: 0)),
            supportedSDKVersions: ExtensionVersionRange(
                minimum: ExtensionVersion(major: 1, minor: 0, patch: 0),
                maximum: ExtensionVersion(major: 2, minor: 0, patch: 0)
            ),
            capabilities: [.openDestination],
            artifactKind: .compiledIn,
            entryPoints: [
                ExtensionEntryPoint(id: "com.notchkit.example.hello.page", kind: .openDestination)
            ],
            defaultEnabled: false,
            source: .firstParty
        )
    }

    static func definition() throws -> ExtensionDefinition {
        ExtensionDefinition(metadata: try metadata()) { context in
            HelloExtension(context: context)
        }
    }
}

/// The activated instance. Owns only what it starts in `activate()`.
@MainActor
final class HelloExtension: NotchExtension {
    private let context: ExtensionContext
    private(set) var activations = 0
    private(set) var isActive = false

    init(context: ExtensionContext) {
        self.context = context
    }

    func activate() async throws {
        isActive = true
        activations += 1
        // Example of registering owned work with the teardown scope.
        let task = Task { /* long-running example work */ }
        context.cancellation.add(task)
    }

    func deactivate() {
        isActive = false
        context.cancellation.cancelAll()
    }

    func openDestinations() -> [NotchOpenDestination] {
        guard isActive else { return [] }
        return [
            NotchOpenDestination(
                id: DestinationID("com.notchkit.example.hello.page"),
                title: "Hello",
                iconSystemName: "hand.wave",
                order: 100,
                isAvailable: { true },
                makeView: { AnyView(Text("Hello from an extension")) }
            )
        ]
    }
}
