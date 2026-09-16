//
//  AccessibilityAuthorization.swift
//  NotchKit
//
//  The single app-side source of truth for the accessibility permission the
//  HUD feature needs.
//
//  The HUD event tap is created in the app process, so the app's own AX trust is
//  authoritative. The XPC helper is never consulted for this gate: its process
//  is a different TCC identity and was the cause of HUD staying permanently
//  blocked while only NotchKit itself was granted accessibility.
//

import ApplicationServices

/// Reads and requests the app's accessibility authorization.
///
/// Status reads never prompt. Only `requestAuthorization()` may prompt, and it
/// must be called from an explicit user action.
protocol AccessibilityAuthorizing: AnyObject {
    /// Whether the app process is currently trusted. Never prompts.
    func isAuthorized() -> Bool
    /// Asks the system to prompt for accessibility. Never treated as a grant by
    /// itself; callers must re-read `isAuthorized()` afterwards.
    func requestAuthorization()
}

/// Production implementation backed by the ApplicationServices trust APIs.
final class SystemAccessibilityAuthorization: AccessibilityAuthorizing {
    func isAuthorized() -> Bool {
        AXIsProcessTrusted()
    }

    func requestAuthorization() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}