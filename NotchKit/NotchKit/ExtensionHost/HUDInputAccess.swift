//
//  HUDInputAccess.swift
//  NotchKit
//
//  The host-owned input-access capability the HUD media-key tap needs.
//
//  This deliberately does NOT use `AXIsProcessTrusted()` as a gate. Accessibility
//  trust is not interchangeable with event-tap capability, and a sandboxed app is
//  not promised to report `true` even when the Accessibility toggle is on. The
//  authoritative test is the tap attempt (`MediaKeyInterceptor`); the Core
//  Graphics preflights below classify a failure as "needs permission" versus
//  "operational" and drive the request UI.
//

import AppKit
import ApplicationServices
import CoreGraphics

/// Reads and requests the input permissions the media-key tap needs.
///
/// Status reads never prompt. Only `requestObservationAccess()` /
/// `requestModificationAccess()` may prompt, from an explicit user action.
protocol InputAccessAuthorizing: AnyObject {
    /// Input Monitoring: observe the event stream (`.listenOnly`).
    func canObserveInput() -> Bool
    /// Input control: modify or suppress the event stream (`.defaultTap`).
    func canModifyInput() -> Bool
    /// Diagnostic only. Never used as the HUD gate.
    func isAccessibilityTrusted() -> Bool

    /// Explicit, user-initiated requests.
    func requestObservationAccess()
    func requestModificationAccess()
}

/// Production implementation backed by the public Core Graphics permission APIs.
final class SystemInputAccessAuthorization: InputAccessAuthorizing {
    func canObserveInput() -> Bool {
        CGPreflightListenEventAccess()
    }

    func canModifyInput() -> Bool {
        CGPreflightPostEventAccess()
    }

    func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func requestObservationAccess() {
        // Surfaces the Input Monitoring request/pane as needed.
        _ = CGRequestListenEventAccess()
    }

    func requestModificationAccess() {
        // `CGRequestPostEventAccess` surfaces the input-control request; the
        // unsandboxed helper additionally surfaces the Accessibility prompt that
        // App Sandbox suppresses in-process (macOS attributes it to this app).
        _ = CGRequestPostEventAccess()
        XPCHelperClient.shared.requestAccessibilityAuthorization()
        openPane("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private func openPane(_ raw: String) {
        guard let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }
}