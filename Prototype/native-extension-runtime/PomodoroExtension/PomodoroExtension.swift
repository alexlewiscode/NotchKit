import Darwin
import ExtensionFoundation
import ExtensionKit
import Foundation

@main
final class PomodoroExtension: AppExtension {
    @AppExtensionPoint.Bind
    var extensionPoint: AppExtensionPoint {
        AppExtensionPoint.Identifier(
            host: "com.notchkit.prototype.native-host",
            name: "native-ui"
        )
    }

    required init() {}

    @MainActor
    var configuration: AppExtensionSceneConfiguration {
        AppExtensionSceneConfiguration(PomodoroScene())
    }
}

private struct PomodoroScene: AppExtensionScene {
    @MainActor
    var body: some AppExtensionScene {
        PrimitiveAppExtensionScene(id: "main") {
            PomodoroView()
        } onConnection: { connection in
            connection.exportedInterface = NSXPCInterface(with: NativeExtensionSceneService.self)
            connection.exportedObject = PomodoroSceneService()
            connection.resume()
            return true
        }
    }
}

private final class PomodoroSceneService: NSObject, NativeExtensionSceneService {
    func handshake(_ requestData: Data, withReply reply: @escaping (Data) -> Void) {
        guard let request = try? NativeExtensionProtocolCodec.decode(
            NativeExtensionHandshakeRequest.self,
            from: requestData
        ), request.protocolVersion == NativeExtensionProtocol.currentVersion,
           request.extensionID == "com.notchkit.prototype.pomodoro",
           request.sceneID == "main"
        else {
            reply(Data())
            return
        }

        let response = NativeExtensionHandshakeResponse(
            protocolVersion: NativeExtensionProtocol.currentVersion,
            extensionID: "com.notchkit.prototype.pomodoro",
            extensionVersion: "1.0.0",
            ready: true
        )
        reply((try? NativeExtensionProtocolCodec.encode(response)) ?? Data())
    }

    func crashForTesting() {
        Darwin._exit(86)
    }
}
