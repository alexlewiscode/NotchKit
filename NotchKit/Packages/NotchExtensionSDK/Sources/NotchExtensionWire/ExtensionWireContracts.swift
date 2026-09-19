//
//  ExtensionWireContracts.swift
//  NotchExtensionWire
//

import Foundation
import NotchExtensionSDK

public enum ExtensionWireProtocol {
    public static let currentVersion = 1
    public static let maximumMessageSize = 64 * 1024
}

public struct ExtensionHandshakeRequest: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let protocolVersion: Int
    public let extensionID: ExtensionIdentity
    public let entryPointID: String

    public init(
        requestID: UUID = UUID(),
        protocolVersion: Int = ExtensionWireProtocol.currentVersion,
        extensionID: ExtensionIdentity,
        entryPointID: String
    ) {
        self.requestID = requestID
        self.protocolVersion = protocolVersion
        self.extensionID = extensionID
        self.entryPointID = entryPointID
    }
}

public struct ExtensionHandshakeResponse: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let protocolVersion: Int
    public let extensionID: ExtensionIdentity
    public let entryPointID: String
    public let extensionVersion: ExtensionVersion
    public let accepted: Bool
    public let failure: ExtensionWireFailure?

    public init(
        requestID: UUID,
        protocolVersion: Int,
        extensionID: ExtensionIdentity,
        entryPointID: String,
        extensionVersion: ExtensionVersion,
        accepted: Bool,
        failure: ExtensionWireFailure? = nil
    ) {
        self.requestID = requestID
        self.protocolVersion = protocolVersion
        self.extensionID = extensionID
        self.entryPointID = entryPointID
        self.extensionVersion = extensionVersion
        self.accepted = accepted
        self.failure = failure
    }
}

public struct ExtensionRenderRequest: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let protocolVersion: Int
    public let extensionID: ExtensionIdentity
    public let entryPointID: String

    public init(
        requestID: UUID = UUID(),
        protocolVersion: Int = ExtensionWireProtocol.currentVersion,
        extensionID: ExtensionIdentity,
        entryPointID: String
    ) {
        self.requestID = requestID
        self.protocolVersion = protocolVersion
        self.extensionID = extensionID
        self.entryPointID = entryPointID
    }
}

public struct ExtensionRenderResponse: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let tree: DeclarativeUITree?
    public let failure: ExtensionWireFailure?

    public init(
        requestID: UUID,
        tree: DeclarativeUITree? = nil,
        failure: ExtensionWireFailure? = nil
    ) {
        self.requestID = requestID
        self.tree = tree
        self.failure = failure
    }
}

public enum ExtensionActionValue: Codable, Equatable, Sendable {
    case bool(Bool)
    case string(String)
    case number(Double)

    private enum ValueType: String, Codable { case bool, string, number }
    private enum CodingKeys: String, CodingKey { case type, value }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ValueType.self, forKey: .type) {
        case .bool: self = .bool(try container.decode(Bool.self, forKey: .value))
        case .string: self = .string(try container.decode(String.self, forKey: .value))
        case .number: self = .number(try container.decode(Double.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .bool(value):
            try container.encode(ValueType.bool, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .string(value):
            try container.encode(ValueType.string, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .number(value):
            guard value.isFinite else {
                throw EncodingError.invalidValue(
                    value,
                    EncodingError.Context(
                        codingPath: encoder.codingPath,
                        debugDescription: "Action numbers must be finite"
                    )
                )
            }
            try container.encode(ValueType.number, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}

public struct ExtensionActionRequest: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let protocolVersion: Int
    public let extensionID: ExtensionIdentity
    public let entryPointID: String
    public let nodeID: String
    public let actionID: String
    public let value: ExtensionActionValue?

    public init(
        requestID: UUID = UUID(),
        protocolVersion: Int = ExtensionWireProtocol.currentVersion,
        extensionID: ExtensionIdentity,
        entryPointID: String,
        nodeID: String,
        actionID: String,
        value: ExtensionActionValue? = nil
    ) {
        self.requestID = requestID
        self.protocolVersion = protocolVersion
        self.extensionID = extensionID
        self.entryPointID = entryPointID
        self.nodeID = nodeID
        self.actionID = actionID
        self.value = value
    }
}

public struct ExtensionActionResponse: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let accepted: Bool
    public let needsRender: Bool
    public let failure: ExtensionWireFailure?
    /// A finite host effect returned only while handling a host-initiated
    /// `performAction` request.
    public let hostAction: ExtensionHostActionCommand?

    public init(
        requestID: UUID,
        accepted: Bool,
        needsRender: Bool = false,
        failure: ExtensionWireFailure? = nil,
        hostAction: ExtensionHostActionCommand? = nil
    ) {
        self.requestID = requestID
        self.accepted = accepted
        self.needsRender = needsRender
        self.failure = failure
        self.hostAction = hostAction
    }
}

/// A finite host-owned effect requested by an extension.
public enum ExtensionHostActionCommand: Codable, Equatable, Sendable {
    case openDestination(entryPointID: String)
    case closeNotch
    case showSneakPeek(kind: String, value: Double?, duration: TimeInterval)
    case hideSneakPeek

    public var declaredAction: ExtensionHostAction {
        switch self {
        case .openDestination: .openDestination
        case .closeNotch: .closeNotch
        case .showSneakPeek: .showSneakPeek
        case .hideSneakPeek: .hideSneakPeek
        }
    }

    private enum CommandType: String, Codable {
        case openDestination = "open-destination"
        case closeNotch = "close-notch"
        case showSneakPeek = "show-sneak-peek"
        case hideSneakPeek = "hide-sneak-peek"
    }

    private enum CodingKeys: String, CodingKey {
        case type, entryPointID, kind, value, duration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(CommandType.self, forKey: .type) {
        case .openDestination:
            self = .openDestination(entryPointID: try container.decode(String.self, forKey: .entryPointID))
        case .closeNotch:
            self = .closeNotch
        case .showSneakPeek:
            self = .showSneakPeek(
                kind: try container.decode(String.self, forKey: .kind),
                value: try container.decodeIfPresent(Double.self, forKey: .value),
                duration: try container.decode(TimeInterval.self, forKey: .duration)
            )
        case .hideSneakPeek:
            self = .hideSneakPeek
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .openDestination(entryPointID):
            try container.encode(CommandType.openDestination, forKey: .type)
            try container.encode(entryPointID, forKey: .entryPointID)
        case .closeNotch:
            try container.encode(CommandType.closeNotch, forKey: .type)
        case let .showSneakPeek(kind, value, duration):
            guard duration.isFinite, value?.isFinite != false else {
                throw EncodingError.invalidValue(
                    duration,
                    EncodingError.Context(
                        codingPath: encoder.codingPath,
                        debugDescription: "Sneak-peek numbers must be finite"
                    )
                )
            }
            try container.encode(CommandType.showSneakPeek, forKey: .type)
            try container.encode(kind, forKey: .kind)
            try container.encodeIfPresent(value, forKey: .value)
            try container.encode(duration, forKey: .duration)
        case .hideSneakPeek:
            try container.encode(CommandType.hideSneakPeek, forKey: .type)
        }
    }
}

public struct ExtensionHostActionRequest: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let protocolVersion: Int
    public let extensionID: ExtensionIdentity
    public let command: ExtensionHostActionCommand

    public init(
        requestID: UUID = UUID(),
        protocolVersion: Int = ExtensionWireProtocol.currentVersion,
        extensionID: ExtensionIdentity,
        command: ExtensionHostActionCommand
    ) {
        self.requestID = requestID
        self.protocolVersion = protocolVersion
        self.extensionID = extensionID
        self.command = command
    }
}

public struct ExtensionHostActionResponse: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let accepted: Bool
    public let failure: ExtensionWireFailure?

    public init(
        requestID: UUID,
        accepted: Bool,
        failure: ExtensionWireFailure? = nil
    ) {
        self.requestID = requestID
        self.accepted = accepted
        self.failure = failure
    }
}

public struct ExtensionWireFailure: Codable, Equatable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public enum ExtensionHostEventKind: String, Codable, CaseIterable, Sendable {
    case activated
    case deactivated
    case appearanceChanged = "appearance-changed"
    case localeChanged = "locale-changed"
}

public struct ExtensionHostEvent: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let kind: ExtensionHostEventKind
    public let entryPointID: String?

    public init(
        protocolVersion: Int = ExtensionWireProtocol.currentVersion,
        kind: ExtensionHostEventKind,
        entryPointID: String? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.kind = kind
        self.entryPointID = entryPointID
    }
}

public enum ExtensionInvalidationReason: String, Codable, CaseIterable, Sendable {
    case deactivated
    case disabled
    case removed
    case hostTerminating = "host-terminating"
    case protocolViolation = "protocol-violation"
}

/// Extension-to-host notification that a previously active session is no
/// longer usable.
public struct ExtensionInvalidationEvent: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let extensionID: ExtensionIdentity
    public let entryPointID: String
    public let reason: ExtensionInvalidationReason

    public init(
        protocolVersion: Int = ExtensionWireProtocol.currentVersion,
        extensionID: ExtensionIdentity,
        entryPointID: String,
        reason: ExtensionInvalidationReason
    ) {
        self.protocolVersion = protocolVersion
        self.extensionID = extensionID
        self.entryPointID = entryPointID
        self.reason = reason
    }
}

public enum ExtensionWireValidationError: Error, Equatable, LocalizedError {
    case unsupportedProtocolVersion(Int)
    case unexpectedExtensionID(expected: ExtensionIdentity, actual: ExtensionIdentity)
    case unexpectedEntryPointID(String)
    case requestIDMismatch(expected: UUID, actual: UUID)
    case undeclaredHostAction(ExtensionHostAction)
    case missingHostActionPolicy
    case invalidActionNumber
    case invalidHostAction

    public var errorDescription: String? {
        switch self {
        case let .unsupportedProtocolVersion(version):
            "Unsupported extension wire protocol version: \(version)"
        case let .unexpectedExtensionID(expected, actual):
            "Extension identity mismatch; expected \(expected), found \(actual)"
        case let .unexpectedEntryPointID(id):
            "Unexpected extension entry point: \(id)"
        case let .requestIDMismatch(expected, actual):
            "Request correlation mismatch; expected \(expected), found \(actual)"
        case let .undeclaredHostAction(action):
            "Extension requested an undeclared host action: \(action.rawValue)"
        case .missingHostActionPolicy:
            "Returned host action cannot be validated without manifest policy"
        case .invalidActionNumber:
            "Action numbers must be finite"
        case .invalidHostAction:
            "Host action contains invalid values"
        }
    }
}

public enum ExtensionWireValidator {
    public static func validate(
        _ request: ExtensionHandshakeRequest,
        expectedExtensionID: ExtensionIdentity,
        entryPointIDs: Set<String>,
        supportedProtocolVersions: ExtensionProtocolVersionRange
    ) throws {
        guard supportedProtocolVersions.contains(request.protocolVersion) else {
            throw ExtensionWireValidationError.unsupportedProtocolVersion(request.protocolVersion)
        }
        guard request.extensionID == expectedExtensionID else {
            throw ExtensionWireValidationError.unexpectedExtensionID(
                expected: expectedExtensionID,
                actual: request.extensionID
            )
        }
        guard entryPointIDs.contains(request.entryPointID) else {
            throw ExtensionWireValidationError.unexpectedEntryPointID(request.entryPointID)
        }
    }

    public static func validate(
        _ response: ExtensionHandshakeResponse,
        for request: ExtensionHandshakeRequest
    ) throws {
        try validateCorrelation(response.requestID, expected: request.requestID)
        guard response.protocolVersion == request.protocolVersion else {
            throw ExtensionWireValidationError.unsupportedProtocolVersion(response.protocolVersion)
        }
        guard response.extensionID == request.extensionID else {
            throw ExtensionWireValidationError.unexpectedExtensionID(
                expected: request.extensionID,
                actual: response.extensionID
            )
        }
        guard response.entryPointID == request.entryPointID else {
            throw ExtensionWireValidationError.unexpectedEntryPointID(response.entryPointID)
        }
    }

    public static func validate(
        _ request: ExtensionRenderRequest,
        expectedExtensionID: ExtensionIdentity,
        entryPointIDs: Set<String>
    ) throws {
        try validateEndpoint(
            protocolVersion: request.protocolVersion,
            extensionID: request.extensionID,
            entryPointID: request.entryPointID,
            expectedExtensionID: expectedExtensionID,
            entryPointIDs: entryPointIDs
        )
    }

    public static func validate(
        _ request: ExtensionActionRequest,
        expectedExtensionID: ExtensionIdentity,
        entryPointIDs: Set<String>
    ) throws {
        try validateEndpoint(
            protocolVersion: request.protocolVersion,
            extensionID: request.extensionID,
            entryPointID: request.entryPointID,
            expectedExtensionID: expectedExtensionID,
            entryPointIDs: entryPointIDs
        )
        if case let .number(value)? = request.value, !value.isFinite {
            throw ExtensionWireValidationError.invalidActionNumber
        }
    }

    public static func validate(
        _ request: ExtensionHostActionRequest,
        expectedExtensionID: ExtensionIdentity,
        declaredActions: Set<ExtensionHostAction>,
        entryPointIDs: Set<String>
    ) throws {
        guard request.protocolVersion == ExtensionWireProtocol.currentVersion else {
            throw ExtensionWireValidationError.unsupportedProtocolVersion(request.protocolVersion)
        }
        guard request.extensionID == expectedExtensionID else {
            throw ExtensionWireValidationError.unexpectedExtensionID(
                expected: expectedExtensionID,
                actual: request.extensionID
            )
        }
        guard declaredActions.contains(request.command.declaredAction) else {
            throw ExtensionWireValidationError.undeclaredHostAction(request.command.declaredAction)
        }
        switch request.command {
        case let .openDestination(entryPointID):
            guard entryPointIDs.contains(entryPointID) else {
                throw ExtensionWireValidationError.unexpectedEntryPointID(entryPointID)
            }
        case let .showSneakPeek(kind, value, duration):
            guard !kind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  duration.isFinite, duration >= 0,
                  value?.isFinite != false else {
                throw ExtensionWireValidationError.invalidHostAction
            }
        case .closeNotch, .hideSneakPeek:
            break
        }
    }

    public static func validate(_ response: ExtensionRenderResponse, for request: ExtensionRenderRequest) throws {
        try validateCorrelation(response.requestID, expected: request.requestID)
        if let tree = response.tree {
            try DeclarativeUIValidator.validate(tree)
        }
    }

    public static func validate(
        _ response: ExtensionActionResponse,
        for request: ExtensionActionRequest,
        declaredActions: Set<ExtensionHostAction>? = nil,
        entryPointIDs: Set<String>? = nil
    ) throws {
        try validateCorrelation(response.requestID, expected: request.requestID)
        guard let command = response.hostAction else { return }
        guard let declaredActions, let entryPointIDs else {
            throw ExtensionWireValidationError.missingHostActionPolicy
        }
        let hostActionRequest = ExtensionHostActionRequest(
            protocolVersion: request.protocolVersion,
            extensionID: request.extensionID,
            command: command
        )
        try validate(
            hostActionRequest,
            expectedExtensionID: request.extensionID,
            declaredActions: declaredActions,
            entryPointIDs: entryPointIDs
        )
    }

    public static func validate(
        _ response: ExtensionHostActionResponse,
        for request: ExtensionHostActionRequest
    ) throws {
        try validateCorrelation(response.requestID, expected: request.requestID)
    }

    public static func validate(
        _ event: ExtensionInvalidationEvent,
        expectedExtensionID: ExtensionIdentity,
        entryPointIDs: Set<String>
    ) throws {
        try validateEndpoint(
            protocolVersion: event.protocolVersion,
            extensionID: event.extensionID,
            entryPointID: event.entryPointID,
            expectedExtensionID: expectedExtensionID,
            entryPointIDs: entryPointIDs
        )
    }

    private static func validateEndpoint(
        protocolVersion: Int,
        extensionID: ExtensionIdentity,
        entryPointID: String,
        expectedExtensionID: ExtensionIdentity,
        entryPointIDs: Set<String>
    ) throws {
        guard protocolVersion == ExtensionWireProtocol.currentVersion else {
            throw ExtensionWireValidationError.unsupportedProtocolVersion(protocolVersion)
        }
        guard extensionID == expectedExtensionID else {
            throw ExtensionWireValidationError.unexpectedExtensionID(
                expected: expectedExtensionID,
                actual: extensionID
            )
        }
        guard entryPointIDs.contains(entryPointID) else {
            throw ExtensionWireValidationError.unexpectedEntryPointID(entryPointID)
        }
    }

    private static func validateCorrelation(_ actual: UUID, expected: UUID) throws {
        guard actual == expected else {
            throw ExtensionWireValidationError.requestIDMismatch(expected: expected, actual: actual)
        }
    }
}

public enum ExtensionWireCodecError: Error, Equatable, LocalizedError {
    case messageTooLarge(actual: Int, maximum: Int)
    case malformedMessage

    public var errorDescription: String? {
        switch self {
        case let .messageTooLarge(actual, maximum):
            "Extension wire message is \(actual) bytes; maximum is \(maximum)"
        case .malformedMessage:
            "Extension wire message is malformed"
        }
    }
}

/// JSON transport with the same hard payload limit in both directions.
public enum ExtensionWireCodec {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let data: Data
        do {
            data = try JSONEncoder().encode(value)
        } catch {
            throw ExtensionWireCodecError.malformedMessage
        }
        try checkSize(data)
        return data
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try checkSize(data)
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ExtensionWireCodecError.malformedMessage
        }
    }

    private static func checkSize(_ data: Data) throws {
        guard data.count <= ExtensionWireProtocol.maximumMessageSize else {
            throw ExtensionWireCodecError.messageTooLarge(
                actual: data.count,
                maximum: ExtensionWireProtocol.maximumMessageSize
            )
        }
    }
}

/// Extension-side request endpoint. Codable values are encoded into `Data`;
/// arbitrary Swift values never become NSXPC arguments.
@objc public protocol NotchExtensionServiceProtocol {
    func handshake(_ requestData: Data, withReply reply: @escaping (Data) -> Void)
    func render(_ requestData: Data, withReply reply: @escaping (Data) -> Void)
    func performAction(_ requestData: Data, withReply reply: @escaping (Data) -> Void)
}

/// Host-side event endpoint exported to an extension connection.
@objc public protocol NotchExtensionHostEventProtocol {
    func receiveHostEvent(_ eventData: Data)
}

/// Extension-to-host lifecycle callback carried as bounded encoded `Data`.
@objc public protocol NotchExtensionHostInvalidationProtocol {
    func extensionDidInvalidate(_ eventData: Data)
}

/// Extension-to-host requests for finite, declared host-owned effects.
@objc public protocol NotchExtensionHostActionProtocol {
    func requestHostAction(_ requestData: Data, withReply reply: @escaping (Data) -> Void)
}
