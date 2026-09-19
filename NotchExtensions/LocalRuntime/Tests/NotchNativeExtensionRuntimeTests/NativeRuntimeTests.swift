import Foundation
import NotchExtensionInstallation
import NotchExtensionSDK
import NotchExtensionWire
@testable import NotchNativeExtensionRuntime
import XCTest

final class NativeRuntimeTests: XCTestCase {
    func testMatchingRequiresBundleAndExtensionPointIdentifiers() throws {
        let manifest = try makeManifest()
        let record = makeRecord(manifest: manifest)
        let identities = [
            NativeExtensionIdentityDescriptor(
                id: "wrong-point",
                bundleIdentifier: "com.example.provider.Timer",
                extensionPointIdentifier: "com.example.other"
            ),
            NativeExtensionIdentityDescriptor(
                id: "match",
                bundleIdentifier: "com.example.provider.Timer",
                extensionPointIdentifier: "com.example.point"
            ),
        ]

        let matches = try NativeExtensionMatcher.match(
            candidates: [.init(record: record, manifest: manifest)],
            identities: identities
        )

        XCTAssertEqual(matches.map(\.identity.id), ["match"])
    }

    func testMatchingRejectsAmbiguousSystemIdentities() throws {
        let manifest = try makeManifest()
        let record = makeRecord(manifest: manifest)
        let identity = NativeExtensionIdentityDescriptor(
            id: "one",
            bundleIdentifier: "com.example.provider.Timer",
            extensionPointIdentifier: "com.example.point"
        )
        XCTAssertThrowsError(try NativeExtensionMatcher.match(
            candidates: [.init(record: record, manifest: manifest)],
            identities: [identity, .init(
                id: "two",
                bundleIdentifier: identity.bundleIdentifier,
                extensionPointIdentifier: identity.extensionPointIdentifier
            )]
        )) {
            XCTAssertEqual($0 as? NativeExtensionMatchingError, .ambiguousIdentity(record.id))
        }
    }

    func testLifecycleIncludesApprovalDisabledAndInterruptionPhases() throws {
        var lifecycle = NativeExtensionLifecycle()
        try lifecycle.apply(.approvalRequired)
        XCTAssertEqual(lifecycle.phase, .awaitingApproval)
        try lifecycle.apply(.discovered)
        try lifecycle.apply(.connect)
        try lifecycle.apply(.connectionReady)
        try lifecycle.apply(.handshakeSucceeded)
        try lifecycle.apply(.interrupted)
        XCTAssertEqual(lifecycle.phase, .interrupted)
        try lifecycle.apply(.disabled)
        XCTAssertEqual(lifecycle.phase, .disabled)
    }

    func testReconnectPolicyAllowsExactlyOneReconnect() {
        var policy = NativeExtensionReconnectPolicy(maximumReconnects: 1, delay: .seconds(2))
        XCTAssertEqual(policy.nextDelay(), .seconds(2))
        XCTAssertNil(policy.nextDelay())
        policy.reset()
        XCTAssertEqual(policy.nextDelay(), .seconds(2))
    }

    @MainActor
    func testInjectedSessionValidatesHandshakeAndFetchesRender() async throws {
        let manifest = try makeManifest()
        let transport = FakeTransport(manifest: manifest)
        let session = NativeDeclarativeExtensionSession(
            manifest: manifest,
            entryPointID: "main",
            timeout: .seconds(1),
            transportFactory: { transport }
        )

        try await session.start()
        let tree = try await session.fetchRender()

        XCTAssertEqual(session.phase, .active)
        XCTAssertEqual(tree.root.id, "root")
        XCTAssertEqual(transport.requests, [.handshake, .render])
        session.teardown()
        session.teardown()
        XCTAssertEqual(transport.invalidationCount, 1)
    }

    @MainActor
    func testInjectedSessionRejectsWrongExtensionVersion() async throws {
        let manifest = try makeManifest()
        let transport = FakeTransport(manifest: manifest)
        transport.version = ExtensionVersion("2.0.0")!
        let session = NativeDeclarativeExtensionSession(
            manifest: manifest,
            entryPointID: "main",
            transportFactory: { transport }
        )

        do {
            try await session.start()
            XCTFail("Expected handshake to fail")
        } catch {
            XCTAssertEqual(
                error as? NativeExtensionSessionError,
                .versionMismatch(expected: manifest.metadata.extensionVersion, actual: transport.version)
            )
        }
        guard case .failed = session.phase else { return XCTFail("Expected failed phase") }
    }

    @MainActor
    func testSessionReconnectsOnceThenSuppressesCrashLoop() async throws {
        let manifest = try makeManifest()
        let first = FakeTransport(manifest: manifest)
        let second = FakeTransport(manifest: manifest)
        var transports = [first, second]
        let session = NativeDeclarativeExtensionSession(
            manifest: manifest,
            entryPointID: "main",
            reconnectPolicy: .init(maximumReconnects: 1, delay: .zero),
            transportFactory: { transports.removeFirst() }
        )
        try await session.start()

        first.interruptionHandler?()
        for _ in 0..<20 where session.phase != .active {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(session.phase, .active)

        second.interruptionHandler?()
        guard case .failed = session.phase else { return XCTFail("Expected reconnect suppression") }
        XCTAssertEqual(session.lastError as? NativeExtensionSessionError, .reconnectSuppressed)
    }

    @MainActor
    func testHandshakeTimeoutDoesNotWaitForTransportReply() async throws {
        let manifest = try makeManifest()
        let transport = FakeTransport(manifest: manifest)
        transport.hangs = true
        let session = NativeDeclarativeExtensionSession(
            manifest: manifest,
            entryPointID: "main",
            timeout: .milliseconds(10),
            transportFactory: { transport }
        )

        do {
            try await session.start()
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? NativeExtensionSessionError, .timeout)
        }
    }

    @MainActor
    func testUnsolicitedHostActionIsRejectedWithoutCallingHandler() async throws {
        let manifest = try makeManifest()
        let transport = FakeTransport(manifest: manifest)
        var handled: [ExtensionHostActionCommand] = []
        let session = NativeDeclarativeExtensionSession(
            manifest: manifest,
            entryPointID: "main",
            transportFactory: { transport },
            hostActionHandler: { handled.append($0) }
        )
        try await session.start()
        let request = ExtensionHostActionRequest(
            extensionID: manifest.metadata.id,
            command: .openDestination(entryPointID: "main")
        )

        let requestData = try ExtensionWireCodec.encode(request)
        let optionalResponseData = await transport.hostActionHandler?(requestData)
        let responseData = try XCTUnwrap(optionalResponseData)
        let response = try ExtensionWireCodec.decode(ExtensionHostActionResponse.self, from: responseData)

        XCTAssertFalse(response.accepted)
        XCTAssertEqual(response.requestID, request.requestID)
        XCTAssertEqual(response.failure?.code, "user-gesture-required")
        XCTAssertTrue(handled.isEmpty)
    }

    @MainActor
    func testActionResponseInvokesOnlyAllowListedHostAction() async throws {
        let manifest = try makeManifest()
        let transport = FakeTransport(manifest: manifest)
        var handled: [ExtensionHostActionCommand] = []
        let session = NativeDeclarativeExtensionSession(
            manifest: manifest,
            entryPointID: "main",
            transportFactory: { transport },
            hostActionHandler: { handled.append($0) }
        )
        try await session.start()

        transport.actionHostAction = .openDestination(entryPointID: "main")
        _ = try await session.performAction(nodeID: "button", actionID: "open")
        XCTAssertEqual(handled, [.openDestination(entryPointID: "main")])

        transport.actionHostAction = .closeNotch
        do {
            _ = try await session.performAction(nodeID: "button", actionID: "close")
            XCTFail("Expected undeclared host action rejection")
        } catch {
            XCTAssertEqual(error as? ExtensionWireValidationError, .undeclaredHostAction(.closeNotch))
        }
        XCTAssertEqual(handled, [.openDestination(entryPointID: "main")])
    }

    @MainActor
    func testRemoteSceneEntryPointAcceptsHandshakeButRejectsDeclarativeOperations() async throws {
        let manifest = try makeManifest(presentationMode: .remoteScene)
        let transport = FakeTransport(manifest: manifest)
        let session = NativeDeclarativeExtensionSession(
            manifest: manifest,
            entryPointID: "main",
            transportFactory: { transport }
        )

        try await session.start()

        XCTAssertEqual(session.phase, .active)
        XCTAssertEqual(transport.requests, [.handshake])
        do {
            _ = try await session.fetchRender()
            XCTFail("Expected declarative operation rejection")
        } catch {
            XCTAssertEqual(error as? NativeExtensionSessionError, .declarativeEntryPointRequired("main"))
        }
    }
}

@MainActor
private final class FakeTransport: NativeExtensionTransport {
    var interruptionHandler: (@MainActor @Sendable () -> Void)?
    var invalidationHandler: (@MainActor @Sendable () -> Void)?
    var extensionInvalidationHandler: (@MainActor @Sendable (Data) -> Void)?
    var hostActionHandler: (@MainActor @Sendable (Data) async -> Data)?
    var requests: [NativeExtensionRequestKind] = []
    var invalidationCount = 0
    var hangs = false
    var actionHostAction: ExtensionHostActionCommand?
    var version: ExtensionVersion
    let manifest: ExtensionPackageManifest

    init(manifest: ExtensionPackageManifest) {
        self.manifest = manifest
        self.version = manifest.metadata.extensionVersion
    }

    func activate() {}

    func request(_ kind: NativeExtensionRequestKind, data: Data) async throws -> Data {
        requests.append(kind)
        if hangs {
            try await Task.sleep(for: .seconds(60))
            throw CancellationError()
        }
        switch kind {
        case .handshake:
            let request = try ExtensionWireCodec.decode(ExtensionHandshakeRequest.self, from: data)
            return try ExtensionWireCodec.encode(ExtensionHandshakeResponse(
                requestID: request.requestID,
                protocolVersion: request.protocolVersion,
                extensionID: request.extensionID,
                entryPointID: request.entryPointID,
                extensionVersion: version,
                accepted: true
            ))
        case .render:
            let request = try ExtensionWireCodec.decode(ExtensionRenderRequest.self, from: data)
            return try ExtensionWireCodec.encode(ExtensionRenderResponse(
                requestID: request.requestID,
                tree: DeclarativeUITree(root: .init(id: "root", component: .text("Hello")))
            ))
        case .performAction:
            let request = try ExtensionWireCodec.decode(ExtensionActionRequest.self, from: data)
            return try ExtensionWireCodec.encode(ExtensionActionResponse(
                requestID: request.requestID,
                accepted: true,
                hostAction: actionHostAction
            ))
        }
    }

    func invalidate() { invalidationCount += 1 }
}

private func makeManifest(
    presentationMode: ExtensionEntryPointPresentationMode = .declarative
) throws -> ExtensionPackageManifest {
    let id = try ExtensionIdentity("com.example.timer")
    let version = ExtensionVersion("1.2.3")!
    let entryPoint = ExtensionEntryPoint(id: "main", kind: .openDestination)
    let metadata = ExtensionMetadata(
        id: id,
        displayName: "Timer",
        iconSystemName: "timer",
        extensionVersion: version,
        supportedHostVersions: .init(minimum: ExtensionVersion("1.0.0")!),
        supportedSDKVersions: .init(minimum: ExtensionVersion("1.0.0")!),
        capabilities: [.openDestination],
        artifactKind: .appExtension,
        entryPoints: [entryPoint],
        defaultEnabled: true,
        source: .localDeveloper
    )
    return ExtensionPackageManifest(
        metadata: metadata,
        artifact: .init(kind: .appExtension, appExtension: .init(
            providerBundleIdentifier: "com.example.provider",
            extensionBundleIdentifier: "com.example.provider.Timer",
            extensionPointIdentifier: "com.example.point",
            minimumMacOSVersion: ExtensionVersion("26.0.0")!,
            protocolVersions: .init(minimum: 1, maximum: 1),
            architectures: [.arm64]
        )),
        hostActions: [.openDestination],
        entryPoints: [.init(
            entryPoint: entryPoint,
            presentationMode: presentationMode,
            sceneName: presentationMode == .remoteScene ? "main" : nil
        )]
    )
}

private func makeRecord(manifest: ExtensionPackageManifest) -> InstalledExtensionRecord {
    InstalledExtensionRecord(
        id: manifest.metadata.id,
        extensionVersion: manifest.metadata.extensionVersion,
        providerBundleIdentifier: "com.example.provider",
        extensionBundleIdentifiers: ["com.example.provider.Timer"],
        relativeInstallPath: "Extensions/\(manifest.metadata.id.rawValue)",
        manifestSHA256: String(repeating: "a", count: 64),
        declaredPermissions: [],
        declaredHostActions: manifest.hostActions,
        signature: .init(
            teamIdentifier: "TEAM",
            providerDesignatedRequirement: "provider",
            extensionDesignatedRequirements: [:]
        ),
        installedAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 1),
        desiredEnabled: true,
        localStatus: .installed
    )
}
