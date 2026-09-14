//
//  ExampleExtensionContractTests.swift
//  NotchExtensionRuntimeTests
//
//  Compiles the reference example shape and exercises the instance lifecycle.
//

import XCTest
import NotchExtensionSDK
import SwiftUI

private final class Counter {
    var value = 0
}

private final class ExampleHelloExtension: NotchExtension {
    private let context: ExtensionContext
    private(set) var isActive = false
    let teardowns = Counter()

    init(context: ExtensionContext) {
        self.context = context
    }

    func activate() async throws {
        isActive = true
        let teardowns = self.teardowns
        context.cancellation.add { teardowns.value += 1 }
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

@MainActor
final class ExampleExtensionContractTests: XCTestCase {
    private func makeContext(for id: ExtensionIdentity) -> ExtensionContext {
        ExtensionContext(
            identity: id,
            cancellation: ExtensionCancellationBag(),
            presentation: TestPresentationService(),
            store: TestScopedStore(),
            permissions: TestPermissionService()
        )
    }

    private func exampleMetadata() throws -> ExtensionMetadata {
        try JSONDecoder().decode(
            ExtensionMetadata.self,
            from: Data(ExtensionMetadataTests.helloManifestJSON.utf8)
        )
    }

    func testExampleDefinitionBuildsFromManifest() throws {
        let metadata = try exampleMetadata()
        let definition = ExtensionDefinition(metadata: metadata) { context in
            ExampleHelloExtension(context: context)
        }
        XCTAssertEqual(definition.id.rawValue, "com.notchkit.example.hello")
    }

    func testCreatingADefinitionDoesNotInstantiate() throws {
        let metadata = try exampleMetadata()
        var instantiated = false
        _ = ExtensionDefinition(metadata: metadata) { context in
            instantiated = true
            return ExampleHelloExtension(context: context)
        }
        XCTAssertFalse(instantiated, "metadata listing must not create an instance")
    }

    func testActivationExposesContributionsAndDeactivationTearsDown() async throws {
        let metadata = try exampleMetadata()
        let context = makeContext(for: metadata.id)
        let instance = ExampleHelloExtension(context: context)

        try await instance.activate()
        XCTAssertEqual(instance.openDestinations().count, 1)

        instance.deactivate()
        XCTAssertTrue(instance.openDestinations().isEmpty)
        XCTAssertEqual(instance.teardowns.value, 1)
    }

    func testFailedActivationLeavesNoContributions() async throws {
        let metadata = try exampleMetadata()
        let extensionUnderTest = TestLifecycleExtension()
        extensionUnderTest.failOnActivate = true
        extensionUnderTest.lastContext = makeContext(for: metadata.id)

        do {
            try await extensionUnderTest.activate()
            XCTFail("expected activation to throw")
        } catch {
            extensionUnderTest.deactivate()
        }
        XCTAssertTrue(extensionUnderTest.openDestinations().isEmpty)
    }

    func testPresentationServiceRecordsDisplayTargetedRequests() {
        let service = TestPresentationService()
        service.request(
            .open(DestinationID("com.notchkit.example.hello.page")),
            target: .display(DisplayID("display-1"))
        )
        XCTAssertEqual(
            service.calls,
            [
                .init(
                    request: .open(DestinationID("com.notchkit.example.hello.page")),
                    target: .display(DisplayID("display-1"))
                )
            ]
        )
    }
}