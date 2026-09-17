//
//  HostRuntimeServices.swift
//  NotchKit
//
//  App-side implementations of the narrow SDK host services.
//

import AVFoundation
import NotchExtensionSDK
import NotchExtensionRuntime

/// Applies extension presentation requests to per-display routers.
///
/// Extensions can request opening a destination; closing and sneak-peek
/// requests are accepted by the contract but not wired to core in this phase.
@MainActor
final class HostPresentationService: NotchPresentationService {
    private let coordinator: PresentationCoordinator
    private let viewCoordinator: BoringViewCoordinator
    private let activeDisplay: @MainActor () -> DisplayID

    init(
        coordinator: PresentationCoordinator,
        viewCoordinator: BoringViewCoordinator,
        activeDisplay: @escaping @MainActor () -> DisplayID
    ) {
        self.coordinator = coordinator
        self.viewCoordinator = viewCoordinator
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
            case .showSneakPeek(let kind, let value, _):
                // Core owns how (and whether) a transient expanding view is
                // shown. Battery is the only compiled-in contributor that uses
                // this today.
                if kind == "battery" {
                    viewCoordinator.toggleExpandingView(
                        status: true,
                        type: .battery,
                        value: CGFloat(value ?? 0)
                    )
                }
            case .close, .hideSneakPeek:
                // Core owns closing and sneak-peek timing; not wired this phase.
                break
            }
        }
    }
}

/// Answers permission queries through existing host utilities.
///
/// The HUD input capability is read from, and requested in, the app process —
/// the process that owns the media-key event tap. This is the only HUD
/// permission gate in the app.
@MainActor
final class HostPermissionService: NotchPermissionService {
    /// Shared instance for callers that are not an activated extension (views
    /// and the runtime). Extensions receive the same service through their
    /// `ExtensionContext`.
    static let shared = HostPermissionService()

    private let inputAccess: InputAccessAuthorizing

    init(inputAccess: InputAccessAuthorizing = SystemInputAccessAuthorization()) {
        self.inputAccess = inputAccess
    }

    func status(for permission: NotchPermission) -> NotchPermissionStatus {
        switch permission {
        case .accessibility:
            switch inputAccess.status() {
            case .granted: return .authorized
            case .requiresPermission: return .notDetermined
            case .checkFailed: return .restricted
            }
        case .camera:
            return Self.map(AVCaptureDevice.authorizationStatus(for: .video))
        case .mediaControl, .screenRecording:
            return .notDetermined
        }
    }

    func request(_ permission: NotchPermission) async -> NotchPermissionStatus {
        switch permission {
        case .accessibility:
            // Prompting is asynchronous: this only *asks*. Callers re-read.
            requestHUDInputAccess()
        case .camera, .mediaControl, .screenRecording:
            break
        }
        return status(for: permission)
    }

    // MARK: - HUD input capability

    var hudInputAccessStatus: HUDInputAccessStatus { inputAccess.status() }

    var hasHUDInputAccess: Bool { hudInputAccessStatus == .granted }

    /// Explicit, user-initiated request for the input access HUD needs.
    func requestHUDInputAccess() {
        inputAccess.requestAccess()
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
