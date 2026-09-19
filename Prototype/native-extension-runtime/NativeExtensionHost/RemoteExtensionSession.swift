import ExtensionFoundation
import ExtensionKit
import Foundation
import Observation

@MainActor
@Observable
final class RemoteExtensionSession {
    private(set) var phase: NativeExtensionLifecyclePhase = .inactive
    private(set) var errorMessage: String?

    private var lifecycle = NativeExtensionLifecycle(phase: .inactive)
    private var connection: NSXPCConnection?
    private var generation = 0

    func beginActivation() {
        generation &+= 1
        connection?.invalidate()
        connection = nil
        transition(.activate)
        errorMessage = nil
    }

    func didActivate(
        _ viewController: EXHostViewController,
        identity: AppExtensionIdentity,
        extensionID: String,
        sceneID: String
    ) {
        let currentGeneration = generation
        do {
            let connection = try viewController.makeXPCConnection()
            connection.remoteObjectInterface = NSXPCInterface(with: NativeExtensionSceneService.self)
            connection.interruptionHandler = { [weak self] in
                Task { @MainActor in
                    self?.handleInterruption(generation: currentGeneration, message: "Connection interrupted")
                }
            }
            connection.invalidationHandler = { [weak self] in
                Task { @MainActor in
                    self?.handleInterruption(generation: currentGeneration, message: "Connection invalidated")
                }
            }
            connection.resume()
            self.connection = connection

            let request = NativeExtensionHandshakeRequest(
                protocolVersion: NativeExtensionProtocol.currentVersion,
                extensionID: extensionID,
                sceneID: sceneID
            )
            let requestData = try NativeExtensionProtocolCodec.encode(request)
            guard let service = connection.remoteObjectProxyWithErrorHandler({ [weak self] error in
                Task { @MainActor in
                    self?.fail(generation: currentGeneration, message: error.localizedDescription)
                }
            }) as? NativeExtensionSceneService else {
                fail(generation: currentGeneration, message: "Extension service proxy is unavailable")
                return
            }

            service.handshake(requestData) { [weak self] responseData in
                Task { @MainActor in
                    self?.finishHandshake(
                        responseData,
                        expectedExtensionID: request.extensionID,
                        generation: currentGeneration
                    )
                }
            }
        } catch {
            fail(generation: currentGeneration, message: error.localizedDescription)
        }
    }

    func didDeactivate(error: Error?) {
        generation &+= 1
        connection?.invalidate()
        connection = nil
        if let error {
            transition(.interrupted)
            errorMessage = error.localizedDescription
        } else {
            transition(.deactivate)
            errorMessage = nil
        }
    }

    func deactivate() {
        generation &+= 1
        connection?.invalidate()
        connection = nil
        transition(.deactivate)
        errorMessage = nil
    }

    func crashForTesting() {
        guard phase == .active, let connection else { return }
        let currentGeneration = generation
        guard let service = connection.remoteObjectProxyWithErrorHandler({ [weak self] error in
            Task { @MainActor in
                self?.fail(generation: currentGeneration, message: error.localizedDescription)
            }
        }) as? NativeExtensionSceneService else {
            fail(generation: currentGeneration, message: "Extension service proxy is unavailable")
            return
        }
        service.crashForTesting()
    }

    private func finishHandshake(
        _ responseData: Data,
        expectedExtensionID: String,
        generation: Int
    ) {
        guard self.generation == generation else { return }
        do {
            let response = try NativeExtensionProtocolCodec.decode(
                NativeExtensionHandshakeResponse.self,
                from: responseData
            )
            try NativeExtensionProtocolCodec.validate(
                response,
                expectedExtensionID: expectedExtensionID
            )
            guard response.ready else {
                fail(generation: generation, message: "Extension reported that it is not ready")
                return
            }
            transition(.didActivate)
        } catch {
            fail(generation: generation, message: error.localizedDescription)
        }
    }

    private func handleInterruption(generation: Int, message: String) {
        guard self.generation == generation else { return }
        self.generation &+= 1
        connection = nil
        transition(.interrupted)
        errorMessage = message
    }

    private func fail(generation: Int, message: String) {
        guard self.generation == generation else { return }
        self.generation &+= 1
        connection?.invalidate()
        connection = nil
        transition(.fail)
        errorMessage = message
    }

    private func transition(_ event: NativeExtensionLifecycleEvent) {
        do {
            try lifecycle.apply(event)
            phase = lifecycle.phase
        } catch {
            lifecycle = NativeExtensionLifecycle(phase: .failed)
            phase = .failed
            errorMessage = "Invalid lifecycle transition"
        }
    }
}
