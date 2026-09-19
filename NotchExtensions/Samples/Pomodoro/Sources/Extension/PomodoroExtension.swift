import ExtensionFoundation
import ExtensionKit
import Foundation
import NotchExtensionWire

@main
final class PomodoroExtension: AppExtension {
    @AppExtensionPoint.Bind
    var extensionPoint: AppExtensionPoint {
        AppExtensionPoint.Identifier(host: "com.notchkit.app", name: "native-ui")
    }

    required init() {}

    @MainActor
    var configuration: AppExtensionSceneConfiguration {
        AppExtensionSceneConfiguration(
            PomodoroScene(),
            configuration: ConnectionHandler(onConnection: { connection in
                PomodoroConnection.accept(connection)
            })
        )
    }
}

private struct PomodoroScene: AppExtensionScene {
    @MainActor
    var body: some AppExtensionScene {
        PrimitiveAppExtensionScene(id: "main") {
            PomodoroView()
        } onConnection: { connection in
            PomodoroConnection.accept(connection)
        }
    }
}

private enum PomodoroConnection {
    static func accept(_ connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: NotchExtensionServiceProtocol.self)
        connection.exportedObject = PomodoroExtensionService.shared
        connection.resume()
        return true
    }
}
