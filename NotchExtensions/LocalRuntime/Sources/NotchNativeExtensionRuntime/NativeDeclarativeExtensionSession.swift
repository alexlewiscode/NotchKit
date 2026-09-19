import ExtensionFoundation
import ExtensionKit
import Foundation
import NotchExtensionSDK
import NotchExtensionWire
import Observation

public enum NativeExtensionSessionError: Error, Equatable {
    case timeout
    case handshakeRejected(ExtensionWireFailure?)
    case versionMismatch(expected: ExtensionVersion, actual: ExtensionVersion)
    case remoteFailure(ExtensionWireFailure)
    case inactive
    case reconnectSuppressed
    case declarativeEntryPointRequired(String)
}

@MainActor
@Observable
public final class NativeDeclarativeExtensionSession {
    public typealias TransportFactory = @MainActor @Sendable () async throws -> any NativeExtensionTransport
    public typealias HostActionHandler = @MainActor @Sendable (ExtensionHostActionCommand) async throws -> Void

    public private(set) var phase: NativeExtensionLifecyclePhase
    public private(set) var lastError: Error?
    public private(set) var generation = 0

    public let manifest: ExtensionPackageManifest
    public let entryPointID: String
    public let timeout: Duration

    private let transportFactory: TransportFactory
    private let hostActionHandler: HostActionHandler
    private var lifecycle: NativeExtensionLifecycle
    private var reconnectPolicy: NativeExtensionReconnectPolicy
    private var transport: (any NativeExtensionTransport)?
    private var teardownRequested = false

    public init(
        manifest: ExtensionPackageManifest,
        entryPointID: String,
        timeout: Duration = .seconds(5),
        reconnectPolicy: NativeExtensionReconnectPolicy = .init(),
        transportFactory: @escaping TransportFactory,
        hostActionHandler: @escaping HostActionHandler = { _ in }
    ) {
        self.manifest = manifest
        self.entryPointID = entryPointID
        self.timeout = timeout
        self.reconnectPolicy = reconnectPolicy
        self.transportFactory = transportFactory
        self.hostActionHandler = hostActionHandler
        self.lifecycle = NativeExtensionLifecycle(phase: .discovered)
        self.phase = .discovered
    }

    @available(macOS 26.0, *)
    public convenience init(
        identity: AppExtensionIdentity,
        manifest: ExtensionPackageManifest,
        entryPointID: String,
        timeout: Duration = .seconds(5),
        reconnectPolicy: NativeExtensionReconnectPolicy = .init(),
        hostActionHandler: @escaping HostActionHandler = { _ in }
    ) {
        self.init(
            manifest: manifest,
            entryPointID: entryPointID,
            timeout: timeout,
            reconnectPolicy: reconnectPolicy,
            transportFactory: {
                try NativeExtensionMatcher.validate(identity: identity, manifest: manifest)
                return try await NativeXPCConnectionSession.processSession(for: identity)
            },
            hostActionHandler: hostActionHandler
        )
    }

    @available(macOS 26.0, *)
    public convenience init(
        remoteSceneViewController viewController: EXHostViewController,
        manifest: ExtensionPackageManifest,
        entryPointID: String,
        timeout: Duration = .seconds(5),
        reconnectPolicy: NativeExtensionReconnectPolicy = .init()
    ) {
        self.init(
            manifest: manifest,
            entryPointID: entryPointID,
            timeout: timeout,
            reconnectPolicy: reconnectPolicy,
            transportFactory: {
                try NativeXPCConnectionSession.remoteSceneSession(from: viewController)
            }
        )
    }

    public func start() async throws {
        teardownRequested = false
        reconnectPolicy.reset()
        try await connect()
    }

    public func fetchRender() async throws -> DeclarativeUITree {
        try requireDeclarativeEntryPoint()
        guard phase == .active, let transport else { throw NativeExtensionSessionError.inactive }
        let currentGeneration = generation
        let request = ExtensionRenderRequest(extensionID: manifest.metadata.id, entryPointID: entryPointID)
        let responseData = try await bounded { try await transport.request(.render, data: ExtensionWireCodec.encode(request)) }
        guard generation == currentGeneration else { throw NativeExtensionSessionError.inactive }
        let response = try ExtensionWireCodec.decode(ExtensionRenderResponse.self, from: responseData)
        try ExtensionWireValidator.validate(response, for: request)
        if let failure = response.failure { throw NativeExtensionSessionError.remoteFailure(failure) }
        guard let tree = response.tree else {
            throw NativeExtensionSessionError.remoteFailure(.init(code: "missing-render", message: "Render response has no tree"))
        }
        return tree
    }

    @discardableResult
    public func performAction(
        nodeID: String,
        actionID: String,
        value: ExtensionActionValue? = nil
    ) async throws -> ExtensionActionResponse {
        try requireDeclarativeEntryPoint()
        guard phase == .active, let transport else { throw NativeExtensionSessionError.inactive }
        let currentGeneration = generation
        let request = ExtensionActionRequest(
            extensionID: manifest.metadata.id,
            entryPointID: entryPointID,
            nodeID: nodeID,
            actionID: actionID,
            value: value
        )
        let responseData = try await bounded { try await transport.request(.performAction, data: ExtensionWireCodec.encode(request)) }
        guard generation == currentGeneration else { throw NativeExtensionSessionError.inactive }
        let response = try ExtensionWireCodec.decode(ExtensionActionResponse.self, from: responseData)
        try ExtensionWireValidator.validate(
            response,
            for: request,
            declaredActions: manifest.hostActions,
            entryPointIDs: Set(manifest.entryPoints.map(\.id))
        )
        if let failure = response.failure { throw NativeExtensionSessionError.remoteFailure(failure) }
        if response.accepted, let command = response.hostAction {
            try await hostActionHandler(command)
        }
        return response
    }

    public func teardown() {
        guard !teardownRequested else { return }
        teardownRequested = true
        generation &+= 1
        transport?.invalidate()
        transport = nil
        transition(.deactivate)
        lastError = nil
    }

    private func connect() async throws {
        generation &+= 1
        let currentGeneration = generation
        transition(.connect)
        do {
            let newTransport = try await transportFactory()
            guard generation == currentGeneration, !teardownRequested else {
                newTransport.invalidate()
                throw NativeExtensionSessionError.inactive
            }
            configure(newTransport, generation: currentGeneration)
            transport = newTransport
            newTransport.activate()
            transition(.connectionReady)
            try await handshake(using: newTransport, generation: currentGeneration)
            transition(.handshakeSucceeded)
            lastError = nil
        } catch {
            guard generation == currentGeneration else { throw error }
            transport?.invalidate()
            transport = nil
            transition(.failed(error.localizedDescription))
            lastError = error
            throw error
        }
    }

    private func handshake(using transport: any NativeExtensionTransport, generation: Int) async throws {
        guard manifest.entryPoints.contains(where: { $0.id == entryPointID }),
              let artifact = manifest.artifact.appExtension
        else { throw ExtensionWireValidationError.unexpectedEntryPointID(entryPointID) }
        let request = ExtensionHandshakeRequest(extensionID: manifest.metadata.id, entryPointID: entryPointID)
        guard artifact.protocolVersions.contains(request.protocolVersion) else {
            throw ExtensionWireValidationError.unsupportedProtocolVersion(request.protocolVersion)
        }
        let responseData = try await bounded { try await transport.request(.handshake, data: ExtensionWireCodec.encode(request)) }
        guard self.generation == generation else { throw NativeExtensionSessionError.inactive }
        let response = try ExtensionWireCodec.decode(ExtensionHandshakeResponse.self, from: responseData)
        try ExtensionWireValidator.validate(response, for: request)
        guard response.accepted else { throw NativeExtensionSessionError.handshakeRejected(response.failure) }
        guard response.extensionVersion == manifest.metadata.extensionVersion else {
            throw NativeExtensionSessionError.versionMismatch(
                expected: manifest.metadata.extensionVersion,
                actual: response.extensionVersion
            )
        }
    }

    private func configure(_ transport: any NativeExtensionTransport, generation: Int) {
        transport.interruptionHandler = { [weak self] in self?.connectionEnded(generation: generation) }
        transport.invalidationHandler = { [weak self] in self?.connectionEnded(generation: generation) }
        transport.extensionInvalidationHandler = { [weak self] data in
            self?.extensionInvalidated(data, generation: generation)
        }
        transport.hostActionHandler = { [weak self] data in
            self?.rejectUnsolicitedHostAction(data) ?? Data()
        }
    }

    private func connectionEnded(generation: Int) {
        guard self.generation == generation, !teardownRequested else { return }
        self.generation &+= 1
        transport?.invalidate()
        transport = nil
        transition(.interrupted)
        guard let delay = reconnectPolicy.nextDelay() else {
            let error = NativeExtensionSessionError.reconnectSuppressed
            transition(.failed(error.localizedDescription))
            lastError = error
            return
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !self.teardownRequested else { return }
            do { try await self.connect() }
            catch { self.lastError = error }
        }
    }

    private func extensionInvalidated(_ data: Data, generation: Int) {
        guard self.generation == generation else { return }
        do {
            let event = try ExtensionWireCodec.decode(ExtensionInvalidationEvent.self, from: data)
            try ExtensionWireValidator.validate(
                event,
                expectedExtensionID: manifest.metadata.id,
                entryPointIDs: Set(manifest.entryPoints.map(\.id))
            )
            connectionEnded(generation: generation)
        } catch {
            fail(error)
        }
    }

    private func rejectUnsolicitedHostAction(_ data: Data) -> Data {
        let requestID = (try? ExtensionWireCodec.decode(ExtensionHostActionRequest.self, from: data).requestID) ?? UUID()
        return (try? ExtensionWireCodec.encode(ExtensionHostActionResponse(
            requestID: requestID,
            accepted: false,
            failure: .init(
                code: "user-gesture-required",
                message: "Host actions are accepted only in response to a host-initiated user interaction"
            )
        ))) ?? Data()
    }

    private func requireDeclarativeEntryPoint() throws {
        guard manifest.entryPoints.contains(where: {
            $0.id == entryPointID && $0.presentationMode == .declarative
        }) else { throw NativeExtensionSessionError.declarativeEntryPointRequired(entryPointID) }
    }

    private func fail(_ error: Error) {
        generation &+= 1
        transport?.invalidate()
        transport = nil
        transition(.failed(error.localizedDescription))
        lastError = error
    }

    private func bounded<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let gate = ResultGate(continuation)
            Task {
                do { gate.resume(returning: try await operation()) }
                catch { gate.resume(throwing: error) }
            }
            Task { [timeout] in
                try? await Task.sleep(for: timeout)
                gate.resume(throwing: NativeExtensionSessionError.timeout)
            }
        }
    }

    private func transition(_ event: NativeExtensionLifecycleEvent) {
        do {
            try lifecycle.apply(event)
            phase = lifecycle.phase
        } catch {
            lifecycle = NativeExtensionLifecycle(phase: .failed("Invalid lifecycle transition"))
            phase = lifecycle.phase
            lastError = error
        }
    }
}

private final class ResultGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: Value) {
        take()?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<Value, Error>? {
        lock.lock()
        defer { lock.unlock() }
        defer { continuation = nil }
        return continuation
    }
}
