//
//  HUDInputAccess.swift
//  NotchKit
//
//  The host-owned input-access capability the HUD media-key tap needs.
//
//  The tap attempt is the authoritative capability test. This status provider
//  runs in the same app process and only classifies failures or drives settings.
//

import AppKit
import ApplicationServices
import CoreGraphics

enum HUDInputAccessStatus: Equatable {
    case granted
    case requiresPermission
    case checkFailed(String)
}

/// Reads and requests the Accessibility access the modifying event tap needs.
/// Status reads never prompt. Only `requestAccess()` may prompt.
protocol InputAccessAuthorizing: AnyObject {
    func status() -> HUDInputAccessStatus
    func requestAccess()
    var diagnostics: String { get }
}

/// Production implementation backed by the public Core Graphics permission APIs.
final class SystemInputAccessAuthorization: InputAccessAuthorizing {
    func status() -> HUDInputAccessStatus {
        AXIsProcessTrusted() ? .granted : .requiresPermission
    }

    var diagnostics: String {
        "ax=\(AXIsProcessTrusted()) post=\(CGPreflightPostEventAccess())"
    }

    func requestAccess() {
        // Both requests execute in the process that creates the modifying tap.
        _ = CGRequestPostEventAccess()
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openPane("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private func openPane(_ raw: String) {
        guard let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }
}
