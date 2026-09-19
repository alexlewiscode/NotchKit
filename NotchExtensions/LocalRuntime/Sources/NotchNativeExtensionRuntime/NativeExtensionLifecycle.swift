import Foundation

public enum NativeExtensionLifecyclePhase: Equatable, Sendable {
    case discovered
    case awaitingApproval
    case disabled
    case connecting
    case handshaking
    case active
    case interrupted
    case failed(String)
    case inactive
}

public enum NativeExtensionLifecycleEvent: Equatable, Sendable {
    case discovered
    case approvalRequired
    case disabled
    case connect
    case connectionReady
    case handshakeSucceeded
    case interrupted
    case failed(String)
    case deactivate
}

public enum NativeExtensionLifecycleError: Error, Equatable {
    case invalidTransition(from: NativeExtensionLifecyclePhase, event: NativeExtensionLifecycleEvent)
}

public struct NativeExtensionLifecycle: Equatable, Sendable {
    public private(set) var phase: NativeExtensionLifecyclePhase

    public init(phase: NativeExtensionLifecyclePhase = .discovered) {
        self.phase = phase
    }

    public mutating func apply(_ event: NativeExtensionLifecycleEvent) throws {
        switch (phase, event) {
        case (_, .approvalRequired): phase = .awaitingApproval
        case (_, .disabled): phase = .disabled
        case (_, .deactivate): phase = .inactive
        case (_, let .failed(message)): phase = .failed(message)
        case (.discovered, .connect), (.inactive, .connect), (.interrupted, .connect), (.failed, .connect):
            phase = .connecting
        case (.connecting, .connectionReady): phase = .handshaking
        case (.handshaking, .handshakeSucceeded): phase = .active
        case (.connecting, .interrupted), (.handshaking, .interrupted), (.active, .interrupted):
            phase = .interrupted
        case (.awaitingApproval, .discovered), (.disabled, .discovered), (.inactive, .discovered),
             (.interrupted, .discovered), (.failed, .discovered):
            phase = .discovered
        default:
            throw NativeExtensionLifecycleError.invalidTransition(from: phase, event: event)
        }
    }
}

public struct NativeExtensionReconnectPolicy: Equatable, Sendable {
    public let maximumReconnects: Int
    public let delay: Duration
    public private(set) var reconnectCount: Int

    public init(maximumReconnects: Int = 1, delay: Duration = .milliseconds(250), reconnectCount: Int = 0) {
        self.maximumReconnects = max(0, maximumReconnects)
        self.delay = delay
        self.reconnectCount = max(0, reconnectCount)
    }

    public mutating func nextDelay() -> Duration? {
        guard reconnectCount < maximumReconnects else { return nil }
        reconnectCount += 1
        return delay
    }

    public mutating func reset() {
        reconnectCount = 0
    }
}
