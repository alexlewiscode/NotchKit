import ExtensionFoundation
import ExtensionKit
import NotchExtensionSDK
import NotchExtensionWire
import NotchNativeExtensionRuntime
import os
import SwiftUI

@available(macOS 26.0, *)
struct LocalRemoteExtensionView: NSViewControllerRepresentable {
    let identity: AppExtensionIdentity
    let manifest: ExtensionPackageManifest
    let entryPoint: ExtensionPackageEntryPoint

    func makeCoordinator() -> Coordinator {
        Coordinator(identity: identity, manifest: manifest, entryPoint: entryPoint)
    }

    func makeNSViewController(context: Context) -> EXHostViewController {
        let controller = EXHostViewController()
        controller.delegate = context.coordinator
        controller.placeholderView = context.coordinator.loadingView()
        context.coordinator.configure(controller)
        return controller
    }

    func updateNSViewController(_ controller: EXHostViewController, context: Context) {
        guard context.coordinator.identity != identity
                || context.coordinator.manifest != manifest
                || context.coordinator.entryPoint != entryPoint else { return }
        context.coordinator.update(
            identity: identity,
            manifest: manifest,
            entryPoint: entryPoint,
            controller: controller
        )
    }

    static func dismantleNSViewController(_ controller: EXHostViewController, coordinator: Coordinator) {
        coordinator.teardown()
        controller.delegate = nil
        controller.configuration = nil
    }

    @MainActor
    final class Coordinator: NSObject, EXHostViewControllerDelegate {
        fileprivate var identity: AppExtensionIdentity
        fileprivate var manifest: ExtensionPackageManifest
        fileprivate var entryPoint: ExtensionPackageEntryPoint

        private let logger = Logger(
            subsystem: NotchKitIdentity.bundleIdentifier,
            category: "LocalRemoteExtension"
        )
        private var transport: NativeXPCConnectionSession?
        private var handshakeTask: Task<Void, Never>?
        private var generation = 0

        init(
            identity: AppExtensionIdentity,
            manifest: ExtensionPackageManifest,
            entryPoint: ExtensionPackageEntryPoint
        ) {
            self.identity = identity
            self.manifest = manifest
            self.entryPoint = entryPoint
        }

        func configure(_ controller: EXHostViewController) {
            do {
                try validateDescriptor()
                controller.configuration = .init(
                    appExtension: identity,
                    sceneID: entryPoint.sceneName!
                )
            } catch {
                show(error, on: controller)
            }
        }

        func update(
            identity: AppExtensionIdentity,
            manifest: ExtensionPackageManifest,
            entryPoint: ExtensionPackageEntryPoint,
            controller: EXHostViewController
        ) {
            teardown()
            self.identity = identity
            self.manifest = manifest
            self.entryPoint = entryPoint
            controller.placeholderView = loadingView()
            configure(controller)
        }

        func hostViewControllerDidActivate(_ viewController: EXHostViewController) {
            generation &+= 1
            let currentGeneration = generation
            handshakeTask?.cancel()
            handshakeTask = Task { @MainActor [weak self, weak viewController] in
                guard let self, let viewController else { return }
                do {
                    try await self.handshake(viewController, generation: currentGeneration)
                    guard self.generation == currentGeneration else { return }
                    viewController.placeholderView = NSView()
                } catch is CancellationError {
                    return
                } catch {
                    guard self.generation == currentGeneration else { return }
                    self.show(error, on: viewController)
                }
            }
        }

        func hostViewControllerWillDeactivate(
            _ viewController: EXHostViewController,
            error: (any Error)?
        ) {
            teardownTransport()
            if let error { show(error, on: viewController) }
        }

        func teardown() {
            generation &+= 1
            handshakeTask?.cancel()
            handshakeTask = nil
            teardownTransport()
        }

        fileprivate func loadingView() -> NSView {
            NSHostingView(
                rootView: ProgressView("Starting \(identity.localizedName)...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        }

        private func validateDescriptor() throws {
            try NativeExtensionMatcher.validate(identity: identity, manifest: manifest)
            guard manifest.entryPoints.contains(entryPoint),
                  entryPoint.presentationMode == .remoteScene,
                  let sceneName = entryPoint.sceneName,
                  !sceneName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let artifact = manifest.artifact.appExtension,
                  artifact.protocolVersions.contains(ExtensionWireProtocol.currentVersion)
            else { throw LocalRemoteExtensionError.invalidDescriptor }
        }

        private func handshake(
            _ controller: EXHostViewController,
            generation: Int
        ) async throws {
            try validateDescriptor()
            let transport = try NativeXPCConnectionSession.remoteSceneSession(from: controller)
            self.transport?.invalidate()
            self.transport = transport
            transport.interruptionHandler = { [weak self, weak controller] in
                guard let self, let controller else { return }
                self.show(LocalRemoteExtensionError.connectionInterrupted, on: controller)
            }
            transport.invalidationHandler = { [weak self, weak controller] in
                guard let self, let controller else { return }
                self.show(LocalRemoteExtensionError.connectionInvalidated, on: controller)
            }
            transport.hostActionHandler = { [manifest] data in
                await LocalExtensionHostActions.response(to: data, manifest: manifest)
            }
            transport.activate()

            let request = ExtensionHandshakeRequest(
                extensionID: manifest.metadata.id,
                entryPointID: entryPoint.id
            )
            let responseData = try await bounded {
                try await transport.request(.handshake, data: ExtensionWireCodec.encode(request))
            }
            guard self.generation == generation else { throw CancellationError() }
            let response = try ExtensionWireCodec.decode(
                ExtensionHandshakeResponse.self,
                from: responseData
            )
            try ExtensionWireValidator.validate(response, for: request)
            guard response.accepted else {
                throw LocalRemoteExtensionError.handshakeRejected(response.failure?.message)
            }
            guard response.extensionVersion == manifest.metadata.extensionVersion else {
                throw LocalRemoteExtensionError.versionMismatch
            }
        }

        private func bounded(
            _ operation: @escaping @MainActor @Sendable () async throws -> Data
        ) async throws -> Data {
            try await withThrowingTaskGroup(of: Data.self) { group in
                group.addTask { try await operation() }
                group.addTask {
                    try await Task.sleep(for: .seconds(5))
                    throw LocalRemoteExtensionError.timeout
                }
                guard let value = try await group.next() else {
                    throw LocalRemoteExtensionError.connectionInvalidated
                }
                group.cancelAll()
                return value
            }
        }

        private func teardownTransport() {
            transport?.interruptionHandler = nil
            transport?.invalidationHandler = nil
            transport?.hostActionHandler = nil
            transport?.invalidate()
            transport = nil
        }

        private func show(_ error: Error, on controller: EXHostViewController) {
            teardownTransport()
            logger.error("Remote scene failed: \(error.localizedDescription, privacy: .public)")
            controller.placeholderView = NSHostingView(
                rootView: ContentUnavailableView {
                    Label("Extension Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        }
    }
}

@available(macOS 26.0, *)
private enum LocalRemoteExtensionError: LocalizedError {
    case invalidDescriptor
    case handshakeRejected(String?)
    case versionMismatch
    case timeout
    case connectionInterrupted
    case connectionInvalidated

    var errorDescription: String? {
        switch self {
        case .invalidDescriptor: "The remote scene does not match its signed manifest."
        case .handshakeRejected(let message): message ?? "The extension rejected the handshake."
        case .versionMismatch: "The running extension version does not match the installed manifest."
        case .timeout: "The extension did not complete its handshake in time."
        case .connectionInterrupted: "The extension connection was interrupted."
        case .connectionInvalidated: "The extension connection was invalidated."
        }
    }
}
