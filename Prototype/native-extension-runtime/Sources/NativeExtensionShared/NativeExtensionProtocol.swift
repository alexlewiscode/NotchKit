import Foundation

public enum NativeExtensionProtocol {
    public static let currentVersion = 1
    public static let maximumMessageSize = 64 * 1024
}

public struct NativeExtensionHandshakeRequest: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let extensionID: String
    public let sceneID: String

    public init(protocolVersion: Int, extensionID: String, sceneID: String) {
        self.protocolVersion = protocolVersion
        self.extensionID = extensionID
        self.sceneID = sceneID
    }
}

public struct NativeExtensionHandshakeResponse: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let extensionID: String
    public let extensionVersion: String
    public let ready: Bool

    public init(
        protocolVersion: Int,
        extensionID: String,
        extensionVersion: String,
        ready: Bool
    ) {
        self.protocolVersion = protocolVersion
        self.extensionID = extensionID
        self.extensionVersion = extensionVersion
        self.ready = ready
    }
}

public enum NativeExtensionProtocolError: Error, Equatable, LocalizedError {
    case messageTooLarge(Int)
    case unsupportedProtocolVersion(Int)
    case unexpectedExtensionID(expected: String, actual: String)
    case malformedMessage

    public var errorDescription: String? {
        switch self {
        case let .messageTooLarge(size):
            "Extension message is too large: \(size) bytes"
        case let .unsupportedProtocolVersion(version):
            "Unsupported native extension protocol version: \(version)"
        case let .unexpectedExtensionID(expected, actual):
            "Extension identity mismatch; expected \(expected), found \(actual)"
        case .malformedMessage:
            "Extension message is malformed"
        }
    }
}

public enum NativeExtensionProtocolCodec {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let data = try JSONEncoder().encode(value)
        guard data.count <= NativeExtensionProtocol.maximumMessageSize else {
            throw NativeExtensionProtocolError.messageTooLarge(data.count)
        }
        return data
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard data.count <= NativeExtensionProtocol.maximumMessageSize else {
            throw NativeExtensionProtocolError.messageTooLarge(data.count)
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw NativeExtensionProtocolError.malformedMessage
        }
    }

    public static func validate(
        _ response: NativeExtensionHandshakeResponse,
        expectedExtensionID: String
    ) throws {
        guard response.protocolVersion == NativeExtensionProtocol.currentVersion else {
            throw NativeExtensionProtocolError.unsupportedProtocolVersion(response.protocolVersion)
        }
        guard response.extensionID == expectedExtensionID else {
            throw NativeExtensionProtocolError.unexpectedExtensionID(
                expected: expectedExtensionID,
                actual: response.extensionID
            )
        }
    }
}
