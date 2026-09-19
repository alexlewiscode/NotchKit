import Foundation

public enum NativeExtensionLifecyclePhase: String, Equatable, Sendable {
    case discovered
    case disabled
    case activating
    case active
    case interrupted
    case failed
    case inactive
}

public enum NativeExtensionLifecycleEvent: Equatable, Sendable {
    case systemDisabled
    case activate
    case didActivate
    case interrupted
    case fail
    case deactivate
    case rediscovered
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
        case (.discovered, .systemDisabled):
            phase = .disabled
        case (.discovered, .activate), (.inactive, .activate), (.interrupted, .activate), (.failed, .activate):
            phase = .activating
        case (.activating, .didActivate):
            phase = .active
        case (.activating, .fail), (.active, .fail):
            phase = .failed
        case (.activating, .interrupted), (.active, .interrupted):
            phase = .interrupted
        case (.active, .deactivate), (.activating, .deactivate), (.interrupted, .deactivate),
             (.failed, .deactivate), (.disabled, .deactivate):
            phase = .inactive
        case (.disabled, .rediscovered), (.inactive, .rediscovered), (.failed, .rediscovered):
            phase = .discovered
        case (_, .systemDisabled):
            phase = .disabled
        default:
            throw NativeExtensionLifecycleError.invalidTransition(from: phase, event: event)
        }
    }
}
