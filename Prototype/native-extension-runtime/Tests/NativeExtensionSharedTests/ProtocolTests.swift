import XCTest
@testable import NativeExtensionShared

final class ProtocolTests: XCTestCase {
    func testHandshakeRoundTrips() throws {
        let response = NativeExtensionHandshakeResponse(
            protocolVersion: NativeExtensionProtocol.currentVersion,
            extensionID: "com.notchkit.prototype.pomodoro",
            extensionVersion: "1.0.0",
            ready: true
        )

        let data = try NativeExtensionProtocolCodec.encode(response)
        let decoded = try NativeExtensionProtocolCodec.decode(
            NativeExtensionHandshakeResponse.self,
            from: data
        )

        XCTAssertEqual(decoded, response)
        XCTAssertNoThrow(
            try NativeExtensionProtocolCodec.validate(
                decoded,
                expectedExtensionID: "com.notchkit.prototype.pomodoro"
            )
        )
    }

    func testOversizedMessageIsRejectedBeforeDecode() {
        let data = Data(repeating: 0, count: NativeExtensionProtocol.maximumMessageSize + 1)
        XCTAssertThrowsError(
            try NativeExtensionProtocolCodec.decode(NativeExtensionHandshakeResponse.self, from: data)
        ) { error in
            XCTAssertEqual(
                error as? NativeExtensionProtocolError,
                .messageTooLarge(data.count)
            )
        }
    }

    func testWrongExtensionIdentityIsRejected() {
        let response = NativeExtensionHandshakeResponse(
            protocolVersion: 1,
            extensionID: "com.example.spoofed.extension",
            extensionVersion: "1.0.0",
            ready: true
        )

        XCTAssertThrowsError(
            try NativeExtensionProtocolCodec.validate(
                response,
                expectedExtensionID: "com.notchkit.prototype.pomodoro"
            )
        )
    }

    func testUnsupportedProtocolVersionIsRejected() {
        let response = NativeExtensionHandshakeResponse(
            protocolVersion: NativeExtensionProtocol.currentVersion + 1,
            extensionID: "com.notchkit.prototype.pomodoro",
            extensionVersion: "1.0.0",
            ready: true
        )

        XCTAssertThrowsError(
            try NativeExtensionProtocolCodec.validate(
                response,
                expectedExtensionID: response.extensionID
            )
        ) { error in
            XCTAssertEqual(
                error as? NativeExtensionProtocolError,
                .unsupportedProtocolVersion(response.protocolVersion)
            )
        }
    }
}
