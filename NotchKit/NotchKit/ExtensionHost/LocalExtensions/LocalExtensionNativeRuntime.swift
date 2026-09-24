import ExtensionFoundation
import NotchExtensionInstallation
import NotchExtensionRuntime
import NotchExtensionSDK
import NotchExtensionWire
import NotchNativeExtensionRuntime
import Observation
import SwiftUI

@available(macOS 26.0, *)
@MainActor
final class LocalExtensionNativeRuntime {
    private weak var coordinator: LocalExtensionCoordinator?
    private let monitor = NativeExtensionMonitor(appExtensionPoint: .notchKitNativeUI)
    private var identityByExtensionID: [ExtensionIdentity: AppExtensionIdentity] = [:]
    private var observationGeneration = 0

    init(coordinator: LocalExtensionCoordinator) {
        self.coordinator = coordinator
    }

    func start() async {
        observationGeneration &+= 1
        let generation = observationGeneration
        do {
            try await monitor.start()
            guard generation == observationGeneration else { return }
            reconcile()
            watchMonitor(generation: generation)
        } catch {
            guard generation == observationGeneration else { return }
            coordinator?.applyDiscovery(
                matchedExtensionIDs: [],
                disabledCount: 0,
                unapprovedCount: 0
            )
        }
    }

    func refresh() async {
        monitor.stop()
        await start()
    }

    func reconcileInstalledExtensions() {
        reconcile()
    }

    func view(
        for entryPoint: ExtensionPackageEntryPoint,
        manifest: ExtensionPackageManifest,
        assetsURL: URL?
    ) -> AnyView {
        guard let identity = identityByExtensionID[manifest.metadata.id] else {
            return AnyView(ContentUnavailableView(
                "Extension Unavailable",
                systemImage: "puzzlepiece.extension",
                description: Text("Enable and approve the extension in System Settings.")
            ))
        }
        switch entryPoint.presentationMode {
        case .declarative:
            let session = NativeDeclarativeExtensionSession(
                identity: identity,
                manifest: manifest,
                entryPointID: entryPoint.id,
                hostActionHandler: { command in
                    try LocalExtensionHostActions.handle(command)
                }
            )
            return AnyView(DeclarativeExtensionView(session: session, assetsURL: assetsURL))
        case .remoteScene:
            return AnyView(LocalRemoteExtensionView(
                identity: identity,
                manifest: manifest,
                entryPoint: entryPoint
            ))
        }
    }

    private func reconcile() {
        guard let coordinator else { return }
        let candidates = coordinator.installed.compactMap { item -> NativeExtensionInstallCandidate? in
            guard let manifest = item.manifest,
                  item.record.marketplaceRevocationStatus != .revoked
            else { return nil }
            return NativeExtensionInstallCandidate(record: item.record, manifest: manifest)
        }
        let identities = monitor.identities
        do {
            let matches = try NativeExtensionMatcher.match(
                candidates: candidates,
                identities: identities.map(NativeExtensionMatcher.descriptor(for:))
            )
            let identitiesByID = Dictionary(uniqueKeysWithValues: identities.map { ($0.id, $0) })
            identityByExtensionID = Dictionary(uniqueKeysWithValues: matches.compactMap { match in
                identitiesByID[match.identity.id].map { (match.record.id, $0) }
            })
            coordinator.applyDiscovery(
                matchedExtensionIDs: Set(matches.map { $0.record.id }),
                disabledCount: monitor.disabledCount,
                unapprovedCount: monitor.unapprovedCount
            )
        } catch {
            identityByExtensionID = [:]
            coordinator.applyDiscovery(
                matchedExtensionIDs: [],
                disabledCount: monitor.disabledCount,
                unapprovedCount: monitor.unapprovedCount
            )
        }
    }

    private func watchMonitor(generation: Int) {
        withObservationTracking {
            _ = monitor.identities
            _ = monitor.disabledCount
            _ = monitor.unapprovedCount
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.observationGeneration == generation else { return }
                self.reconcile()
                self.watchMonitor(generation: generation)
            }
        }
    }

}

@available(macOS 26.0, *)
@MainActor
enum LocalExtensionHostActions {
    static func handle(_ command: ExtensionHostActionCommand) throws {
        let service = HostPresentationService(
            coordinator: NotchKitRuntime.shared.presentation,
            viewCoordinator: BoringViewCoordinator.shared,
            activeDisplay: { NotchKitRuntime.shared.activeDisplayID }
        )
        switch command {
        case .openDestination(let entryPointID):
            service.request(.open(DestinationID(entryPointID)), target: .active)
        case .closeNotch:
            service.request(.close, target: .active)
        case .showSneakPeek(let kind, let value, let duration):
            service.request(.showSneakPeek(kind: kind, value: value, duration: duration), target: .active)
        case .hideSneakPeek:
            service.request(.hideSneakPeek, target: .active)
        }
    }

    static func response(
        to data: Data,
        manifest: ExtensionPackageManifest
    ) async -> Data {
        let request: ExtensionHostActionRequest
        do {
            request = try ExtensionWireCodec.decode(ExtensionHostActionRequest.self, from: data)
            try ExtensionWireValidator.validate(
                request,
                expectedExtensionID: manifest.metadata.id,
                declaredActions: manifest.hostActions,
                entryPointIDs: Set(manifest.entryPoints.map(\.id))
            )
            try handle(request.command)
            return try ExtensionWireCodec.encode(
                ExtensionHostActionResponse(requestID: request.requestID, accepted: true)
            )
        } catch {
            let requestID = (try? ExtensionWireCodec.decode(
                ExtensionHostActionRequest.self,
                from: data
            ).requestID) ?? UUID()
            return (try? ExtensionWireCodec.encode(ExtensionHostActionResponse(
                requestID: requestID,
                accepted: false,
                failure: .init(code: "host-action-rejected", message: error.localizedDescription)
            ))) ?? Data()
        }
    }
}
