import Foundation
import NotchExtensionSDK
import NotchExtensionWire
import XCTest

final class ExtensionWireTests: XCTestCase {
    func testHandshakeRoundTripsAndValidatesBothSides() throws {
        let identity = try ExtensionIdentity("com.notchkit.tests.wire")
        let request = ExtensionHandshakeRequest(extensionID: identity, entryPointID: "main")
        let decodedRequest = try ExtensionWireCodec.decode(
            ExtensionHandshakeRequest.self,
            from: ExtensionWireCodec.encode(request)
        )
        try ExtensionWireValidator.validate(
            decodedRequest,
            expectedExtensionID: identity,
            entryPointIDs: ["main"],
            supportedProtocolVersions: .init(minimum: 1, maximum: 2)
        )

        let response = ExtensionHandshakeResponse(
            requestID: request.requestID,
            protocolVersion: request.protocolVersion,
            extensionID: identity,
            entryPointID: "main",
            extensionVersion: ExtensionVersion(major: 1, minor: 0, patch: 0),
            accepted: true
        )
        let decodedResponse = try ExtensionWireCodec.decode(
            ExtensionHandshakeResponse.self,
            from: ExtensionWireCodec.encode(response)
        )
        XCTAssertEqual(decodedResponse, response)
        XCTAssertNoThrow(try ExtensionWireValidator.validate(decodedResponse, for: request))
    }

    func testHandshakeRejectsVersionIdentityAndEntryPointMismatch() throws {
        let identity = try ExtensionIdentity("com.notchkit.tests.wire")
        let other = try ExtensionIdentity("com.notchkit.tests.other")
        let unsupported = ExtensionHandshakeRequest(
            protocolVersion: 3,
            extensionID: identity,
            entryPointID: "main"
        )
        XCTAssertThrowsError(try ExtensionWireValidator.validate(
            unsupported,
            expectedExtensionID: identity,
            entryPointIDs: ["main"],
            supportedProtocolVersions: .init(minimum: 1, maximum: 2)
        )) { XCTAssertEqual($0 as? ExtensionWireValidationError, .unsupportedProtocolVersion(3)) }

        let wrongIdentity = ExtensionHandshakeRequest(extensionID: other, entryPointID: "main")
        XCTAssertThrowsError(try ExtensionWireValidator.validate(
            wrongIdentity,
            expectedExtensionID: identity,
            entryPointIDs: ["main"],
            supportedProtocolVersions: .init(minimum: 1, maximum: 1)
        )) { XCTAssertEqual(
            $0 as? ExtensionWireValidationError,
            .unexpectedExtensionID(expected: identity, actual: other)
        ) }

        let wrongEntryPoint = ExtensionHandshakeRequest(extensionID: identity, entryPointID: "other")
        XCTAssertThrowsError(try ExtensionWireValidator.validate(
            wrongEntryPoint,
            expectedExtensionID: identity,
            entryPointIDs: ["main"],
            supportedProtocolVersions: .init(minimum: 1, maximum: 1)
        )) { XCTAssertEqual($0 as? ExtensionWireValidationError, .unexpectedEntryPointID("other")) }
    }

    func testRenderRequestRoundTripsThroughBoundedCodec() throws {
        let identity = try ExtensionIdentity("com.notchkit.tests.wire")
        let request = ExtensionRenderRequest(
            requestID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            extensionID: identity,
            entryPointID: "main"
        )
        let data = try ExtensionWireCodec.encode(request)
        XCTAssertEqual(try ExtensionWireCodec.decode(ExtensionRenderRequest.self, from: data), request)
        XCTAssertNoThrow(try ExtensionWireValidator.validate(
            request,
            expectedExtensionID: identity,
            entryPointIDs: ["main"]
        ))
    }

    func testRenderResponseCarriesDeclarativeTree() throws {
        let response = ExtensionRenderResponse(
            requestID: UUID(),
            tree: DeclarativeUITree(root: .init(id: "root", component: .text("Hello")))
        )
        XCTAssertEqual(
            try ExtensionWireCodec.decode(
                ExtensionRenderResponse.self,
                from: ExtensionWireCodec.encode(response)
            ),
            response
        )
    }

    func testActionRequestRoundTripsEachFiniteValueType() throws {
        let values: [ExtensionActionValue?] = [nil, .bool(true), .string("value"), .number(1.5)]
        for value in values {
            let request = ExtensionActionRequest(
                extensionID: try ExtensionIdentity("com.notchkit.tests.wire"),
                entryPointID: "main",
                nodeID: "control",
                actionID: "change",
                value: value
            )
            let data = try ExtensionWireCodec.encode(request)
            XCTAssertEqual(try ExtensionWireCodec.decode(ExtensionActionRequest.self, from: data), request)
        }
    }

    func testActionFailureRoundTrips() throws {
        let response = ExtensionActionResponse(
            requestID: UUID(),
            accepted: false,
            failure: ExtensionWireFailure(code: "not-authorized", message: "Permission denied")
        )
        XCTAssertEqual(
            try ExtensionWireCodec.decode(
                ExtensionActionResponse.self,
                from: ExtensionWireCodec.encode(response)
            ),
            response
        )
    }

    func testActionResponseMayReturnDeclaredFiniteHostAction() throws {
        let identity = try ExtensionIdentity("com.notchkit.tests.wire")
        let request = ExtensionActionRequest(
            extensionID: identity,
            entryPointID: "main",
            nodeID: "open",
            actionID: "open"
        )
        let response = ExtensionActionResponse(
            requestID: request.requestID,
            accepted: true,
            hostAction: .openDestination(entryPointID: "main")
        )
        let decoded = try ExtensionWireCodec.decode(
            ExtensionActionResponse.self,
            from: ExtensionWireCodec.encode(response)
        )
        XCTAssertEqual(decoded, response)
        XCTAssertNoThrow(try ExtensionWireValidator.validate(
            decoded,
            for: request,
            declaredActions: [.openDestination],
            entryPointIDs: ["main"]
        ))
    }

    func testReturnedHostActionFailsClosedWithoutManifestPolicy() throws {
        let request = ExtensionActionRequest(
            extensionID: try ExtensionIdentity("com.notchkit.tests.wire"),
            entryPointID: "main",
            nodeID: "close",
            actionID: "close"
        )
        let response = ExtensionActionResponse(
            requestID: request.requestID,
            accepted: true,
            hostAction: .closeNotch
        )
        XCTAssertThrowsError(try ExtensionWireValidator.validate(response, for: request)) { error in
            XCTAssertEqual(error as? ExtensionWireValidationError, .missingHostActionPolicy)
        }
    }

    func testRejectsUndeclaredReturnedHostAction() throws {
        let request = ExtensionActionRequest(
            extensionID: try ExtensionIdentity("com.notchkit.tests.wire"),
            entryPointID: "main",
            nodeID: "close",
            actionID: "close"
        )
        let response = ExtensionActionResponse(
            requestID: request.requestID,
            accepted: true,
            hostAction: .closeNotch
        )
        XCTAssertThrowsError(try ExtensionWireValidator.validate(
            response,
            for: request,
            declaredActions: [],
            entryPointIDs: ["main"]
        )) { error in
            XCTAssertEqual(
                error as? ExtensionWireValidationError,
                .undeclaredHostAction(.closeNotch)
            )
        }
    }

    func testRejectsNonfiniteActionNumberDuringValidationAndEncoding() throws {
        let identity = try ExtensionIdentity("com.notchkit.tests.wire")
        let request = ExtensionActionRequest(
            extensionID: identity,
            entryPointID: "main",
            nodeID: "progress",
            actionID: "change",
            value: .number(.infinity)
        )
        XCTAssertThrowsError(try ExtensionWireValidator.validate(
            request,
            expectedExtensionID: identity,
            entryPointIDs: ["main"]
        )) { XCTAssertEqual($0 as? ExtensionWireValidationError, .invalidActionNumber) }
        XCTAssertThrowsError(try ExtensionWireCodec.encode(request)) { error in
            XCTAssertEqual(error as? ExtensionWireCodecError, .malformedMessage)
        }
    }

    func testFiniteHostActionRequestsRoundTripAndValidate() throws {
        let identity = try ExtensionIdentity("com.notchkit.tests.wire")
        let commands: [ExtensionHostActionCommand] = [
            .openDestination(entryPointID: "main"),
            .closeNotch,
            .showSneakPeek(kind: "volume", value: 0.5, duration: 1.5),
            .hideSneakPeek
        ]
        let declarations = Set(commands.map(\.declaredAction))
        for command in commands {
            let request = ExtensionHostActionRequest(extensionID: identity, command: command)
            let decoded = try ExtensionWireCodec.decode(
                ExtensionHostActionRequest.self,
                from: ExtensionWireCodec.encode(request)
            )
            XCTAssertEqual(decoded, request)
            XCTAssertNoThrow(try ExtensionWireValidator.validate(
                decoded,
                expectedExtensionID: identity,
                declaredActions: declarations,
                entryPointIDs: ["main"]
            ))
        }
    }

    func testHostActionValidationRejectsUndeclaredAndInvalidRequests() throws {
        let identity = try ExtensionIdentity("com.notchkit.tests.wire")
        let undeclared = ExtensionHostActionRequest(extensionID: identity, command: .closeNotch)
        XCTAssertThrowsError(try ExtensionWireValidator.validate(
            undeclared,
            expectedExtensionID: identity,
            declaredActions: [],
            entryPointIDs: ["main"]
        )) { XCTAssertEqual($0 as? ExtensionWireValidationError, .undeclaredHostAction(.closeNotch)) }

        let invalid = ExtensionHostActionRequest(
            extensionID: identity,
            command: .showSneakPeek(kind: " ", value: nil, duration: -1)
        )
        XCTAssertThrowsError(try ExtensionWireValidator.validate(
            invalid,
            expectedExtensionID: identity,
            declaredActions: [.showSneakPeek],
            entryPointIDs: ["main"]
        )) { XCTAssertEqual($0 as? ExtensionWireValidationError, .invalidHostAction) }
    }

    func testResponseCorrelationHelpersRejectMismatchedRequestIDs() throws {
        let identity = try ExtensionIdentity("com.notchkit.tests.wire")
        let actual = UUID()

        let render = ExtensionRenderRequest(extensionID: identity, entryPointID: "main")
        XCTAssertThrowsError(try ExtensionWireValidator.validate(
            ExtensionRenderResponse(requestID: actual),
            for: render
        )) { XCTAssertEqual(
            $0 as? ExtensionWireValidationError,
            .requestIDMismatch(expected: render.requestID, actual: actual)
        ) }

        let action = ExtensionActionRequest(
            extensionID: identity,
            entryPointID: "main",
            nodeID: "button",
            actionID: "tap"
        )
        XCTAssertThrowsError(try ExtensionWireValidator.validate(
            ExtensionActionResponse(requestID: actual, accepted: true),
            for: action
        ))

        let hostAction = ExtensionHostActionRequest(extensionID: identity, command: .closeNotch)
        XCTAssertThrowsError(try ExtensionWireValidator.validate(
            ExtensionHostActionResponse(requestID: actual, accepted: true),
            for: hostAction
        ))
    }

    func testInvalidationCallbackRoundTrips() throws {
        let identity = try ExtensionIdentity("com.notchkit.tests.wire")
        let event = ExtensionInvalidationEvent(
            extensionID: identity,
            entryPointID: "main",
            reason: .protocolViolation
        )
        XCTAssertEqual(
            try ExtensionWireCodec.decode(
                ExtensionInvalidationEvent.self,
                from: ExtensionWireCodec.encode(event)
            ),
            event
        )
        XCTAssertNoThrow(try ExtensionWireValidator.validate(
            event,
            expectedExtensionID: identity,
            entryPointIDs: ["main"]
        ))
    }

    func testHostEventRoundTrips() throws {
        let event = ExtensionHostEvent(kind: .appearanceChanged, entryPointID: "main")
        XCTAssertEqual(
            try ExtensionWireCodec.decode(ExtensionHostEvent.self, from: ExtensionWireCodec.encode(event)),
            event
        )
    }

    func testDecodeRejectsOversizedPayloadBeforeParsing() {
        let data = Data(repeating: 0, count: ExtensionWireProtocol.maximumMessageSize + 1)
        XCTAssertThrowsError(try ExtensionWireCodec.decode(ExtensionHostEvent.self, from: data)) { error in
            XCTAssertEqual(
                error as? ExtensionWireCodecError,
                .messageTooLarge(actual: data.count, maximum: 64 * 1024)
            )
        }
    }

    func testEncodeRejectsOversizedPayload() {
        let failure = ExtensionWireFailure(code: "large", message: String(repeating: "x", count: 66_000))
        XCTAssertThrowsError(try ExtensionWireCodec.encode(failure)) { error in
            guard case let ExtensionWireCodecError.messageTooLarge(actual, maximum) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertGreaterThan(actual, maximum)
            XCTAssertEqual(maximum, 64 * 1024)
        }
    }

    func testDecodeNormalizesMalformedJSON() {
        XCTAssertThrowsError(
            try ExtensionWireCodec.decode(ExtensionHostEvent.self, from: Data("not-json".utf8))
        ) { error in
            XCTAssertEqual(error as? ExtensionWireCodecError, .malformedMessage)
        }
    }

    func testServiceAndHostEventContractsBuildNSXPCInterfaces() {
        let service = NSXPCInterface(with: NotchExtensionServiceProtocol.self)
        let hostEvents = NSXPCInterface(with: NotchExtensionHostEventProtocol.self)
        let invalidation = NSXPCInterface(with: NotchExtensionHostInvalidationProtocol.self)
        let hostActions = NSXPCInterface(with: NotchExtensionHostActionProtocol.self)
        XCTAssertNotNil(service)
        XCTAssertNotNil(hostEvents)
        XCTAssertNotNil(invalidation)
        XCTAssertNotNil(hostActions)
    }

    func testProtocolsCarryDataAtRuntime() {
        let service = ServiceDouble()
        let host = HostEventDouble()
        let payload = Data("payload".utf8)

        var renderReply: Data?
        service.handshake(payload) { _ in }
        service.render(payload) { renderReply = $0 }
        service.performAction(payload) { _ in }
        host.receiveHostEvent(payload)

        XCTAssertEqual(renderReply, payload)
        XCTAssertEqual(service.actionData, payload)
        XCTAssertEqual(host.eventData, payload)
    }
}

private final class ServiceDouble: NSObject, NotchExtensionServiceProtocol {
    var actionData: Data?

    func handshake(_ requestData: Data, withReply reply: @escaping (Data) -> Void) {
        reply(requestData)
    }

    func render(_ requestData: Data, withReply reply: @escaping (Data) -> Void) {
        reply(requestData)
    }

    func performAction(_ requestData: Data, withReply reply: @escaping (Data) -> Void) {
        actionData = requestData
        reply(requestData)
    }
}

private final class HostEventDouble: NSObject, NotchExtensionHostEventProtocol {
    var eventData: Data?

    func receiveHostEvent(_ eventData: Data) {
        self.eventData = eventData
    }
}
