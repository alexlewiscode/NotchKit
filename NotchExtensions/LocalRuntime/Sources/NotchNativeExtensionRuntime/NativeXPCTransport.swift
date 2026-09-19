import ExtensionFoundation
import ExtensionKit
import Foundation
import NotchExtensionWire

public enum NativeExtensionRequestKind: Equatable, Sendable {
    case handshake
    case render
    case performAction
}

@MainActor
public protocol NativeExtensionTransport: AnyObject {
    var interruptionHandler: (@MainActor @Sendable () -> Void)? { get set }
    var invalidationHandler: (@MainActor @Sendable () -> Void)? { get set }
    var extensionInvalidationHandler: (@MainActor @Sendable (Data) -> Void)? { get set }
    var hostActionHandler: (@MainActor @Sendable (Data) async -> Data)? { get set }

    func activate()
    func request(_ kind: NativeExtensionRequestKind, data: Data) async throws -> Data
    func invalidate()
}

public enum NativeExtensionTransportError: Error, Equatable {
    case remoteProxyUnavailable
    case invalidated
}

@objc private protocol NotchExtensionCombinedHostProtocol:
    NotchExtensionHostInvalidationProtocol, NotchExtensionHostActionProtocol {}

@available(macOS 26.0, *)
@MainActor
public final class NativeXPCConnectionSession: NSObject, NativeExtensionTransport {
    public var interruptionHandler: (@MainActor @Sendable () -> Void)?
    public var invalidationHandler: (@MainActor @Sendable () -> Void)?
    public var extensionInvalidationHandler: (@MainActor @Sendable (Data) -> Void)?
    public var hostActionHandler: (@MainActor @Sendable (Data) async -> Data)?

    private let connection: NSXPCConnection
    private let process: AppExtensionProcess?
    private var isActive = false
    private var isInvalidated = false

    public init(connection: NSXPCConnection, process: AppExtensionProcess? = nil) {
        self.connection = connection
        self.process = process
        super.init()
        connection.remoteObjectInterface = NSXPCInterface(with: NotchExtensionServiceProtocol.self)
        connection.exportedInterface = NSXPCInterface(with: NotchExtensionCombinedHostProtocol.self)
        connection.exportedObject = self
        connection.interruptionHandler = { [weak self] in
            Task { @MainActor in self?.interruptionHandler?() }
        }
        connection.invalidationHandler = { [weak self] in
            Task { @MainActor in self?.handleConnectionInvalidation() }
        }
    }

    public func activate() {
        guard !isActive, !isInvalidated else { return }
        isActive = true
        connection.resume()
    }

    public func request(_ kind: NativeExtensionRequestKind, data: Data) async throws -> Data {
        guard !isInvalidated else { throw NativeExtensionTransportError.invalidated }
        return try await withCheckedThrowingContinuation { continuation in
            let gate = ContinuationGate(continuation)
            guard let service = connection.remoteObjectProxyWithErrorHandler({ error in
                gate.resume(throwing: error)
            }) as? NotchExtensionServiceProtocol else {
                gate.resume(throwing: NativeExtensionTransportError.remoteProxyUnavailable)
                return
            }
            let reply: (Data) -> Void = { gate.resume(returning: $0) }
            switch kind {
            case .handshake: service.handshake(data, withReply: reply)
            case .render: service.render(data, withReply: reply)
            case .performAction: service.performAction(data, withReply: reply)
            }
        }
    }

    public func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        connection.interruptionHandler = nil
        connection.invalidationHandler = nil
        connection.invalidate()
        process?.invalidate()
    }

    private func handleConnectionInvalidation() {
        guard !isInvalidated else { return }
        isInvalidated = true
        invalidationHandler?()
    }

    private func handleProcessInterruption() {
        guard !isInvalidated else { return }
        interruptionHandler?()
    }
}

@available(macOS 26.0, *)
extension NativeXPCConnectionSession: NotchExtensionCombinedHostProtocol {
    public nonisolated func extensionDidInvalidate(_ eventData: Data) {
        Task { @MainActor [weak self] in self?.extensionInvalidationHandler?(eventData) }
    }

    public nonisolated func requestHostAction(_ requestData: Data, withReply reply: @escaping (Data) -> Void) {
        Task { @MainActor [weak self] in
            if let handler = self?.hostActionHandler {
                reply(await handler(requestData))
            } else {
                let requestID = (try? ExtensionWireCodec.decode(
                    ExtensionHostActionRequest.self,
                    from: requestData
                ).requestID) ?? UUID()
                let response = ExtensionHostActionResponse(
                    requestID: requestID,
                    accepted: false,
                    failure: .init(
                        code: "user-gesture-required",
                        message: "Host actions require a host-initiated user interaction"
                    )
                )
                reply((try? ExtensionWireCodec.encode(response)) ?? Data())
            }
        }
    }
}

@available(macOS 26.0, *)
public extension NativeXPCConnectionSession {
    @MainActor
    static func processSession(for identity: AppExtensionIdentity) async throws -> NativeXPCConnectionSession {
        let relay = ProcessInterruptionRelay()
        let process = try await AppExtensionProcess(
            configuration: .init(appExtensionIdentity: identity, onInterruption: { relay.signal() })
        )
        let session = NativeXPCConnectionSession(connection: try process.makeXPCConnection(), process: process)
        relay.install {
            Task { @MainActor [weak session] in session?.handleProcessInterruption() }
        }
        return session
    }

    @MainActor
    static func remoteSceneSession(
        from viewController: EXHostViewController
    ) throws -> NativeXPCConnectionSession {
        NativeXPCConnectionSession(connection: try viewController.makeXPCConnection())
    }
}

private final class ProcessInterruptionRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?
    private var pending = false

    func install(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        self.handler = handler
        let shouldSignal = pending
        pending = false
        lock.unlock()
        if shouldSignal { handler() }
    }

    func signal() {
        lock.lock()
        guard let handler else {
            pending = true
            lock.unlock()
            return
        }
        lock.unlock()
        handler()
    }
}

private final class ContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?

    init(_ continuation: CheckedContinuation<Data, Error>) {
        self.continuation = continuation
    }

    func resume(returning data: Data) {
        take()?.resume(returning: data)
    }

    func resume(throwing error: Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<Data, Error>? {
        lock.lock()
        defer { lock.unlock() }
        defer { continuation = nil }
        return continuation
    }
}
