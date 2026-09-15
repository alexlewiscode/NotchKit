//
//  HostRuntimeServices.swift
//  NotchKit
//
//  App-side implementations of the narrow SDK host services.
//

import AVFoundation
import ApplicationServices
import NotchExtensionSDK
import NotchExtensionRuntime

/// Applies extension presentation requests to per-display routers.
///
/// Extensions can request opening a destination; closing and sneak-peek
/// requests are accepted by the contract but not wired to core in this phase.
@MainActor
final class HostPresentationService: NotchPresentationService {
    private let coordinator: PresentationCoordinator
    private let activeDisplay: @MainActor () -> DisplayID

    init(coordinator: PresentationCoordinator, activeDisplay: @escaping @MainActor () -> DisplayID) {
        self.coordinator = coordinator
        self.activeDisplay = activeDisplay
    }

    var availableDisplays: [DisplayID] { coordinator.displayIDs }

    func request(_ request: PresentationRequest, target: PresentationTarget) {
        let displays: [DisplayID]
        switch target.scope {
        case .active:
            displays = [activeDisplay()]
        case .all:
            displays = coordinator.displayIDs
        case .display:
            if let id = target.display,
               id == activeDisplay() || coordinator.displayIDs.contains(id) {
                displays = [id]
            } else {
                displays = [activeDisplay()]
            }
        }

        for display in displays {
            let router = coordinator.router(for: display)
            switch request {
            case .open(let destination):
                router.select(destination)
            case .close, .showSneakPeek, .hideSneakPeek:
                // Core owns closing and sneak-peek timing; not wired this phase.
                break
            }
        }
    }
}

/// Answers permission queries through existing host utilities.
@MainActor
final class HostPermissionService: NotchPermissionService {
    func status(for permission: NotchPermission) -> NotchPermissionStatus {
        switch permission {
        case .accessibility:
            return AXIsProcessTrusted() ? .authorized : .notDetermined
        case .camera:
            return Self.map(AVCaptureDevice.authorizationStatus(for: .video))
        case .mediaControl, .screenRecording:
            return .notDetermined
        }
    }

    func request(_ permission: NotchPermission) async -> NotchPermissionStatus {
        status(for: permission)
    }

    private static func map(_ status: AVAuthorizationStatus) -> NotchPermissionStatus {
        switch status {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }
}
