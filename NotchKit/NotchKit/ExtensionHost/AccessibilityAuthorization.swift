//
//  AccessibilityAuthorization.swift
//  NotchKit
//
//  The single app-side source of truth for the accessibility permission the
//  HUD feature needs.
//
//  The HUD event tap is created in the app process, so the app's own AX trust is
//  authoritative — the XPC helper's process is a different identity and must
//  never be used as the gate. The helper *is* used as the prompt channel: App
//  Sandbox suppresses the in-process AX prompt, and macOS attributes the
//  helper's request to this (responsible) app.
//

import AppKit
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

/// Production implementation: app-side trust, with prompting routed through the
/// unsandboxed helper.
final class SystemAccessibilityAuthorization: AccessibilityAuthorizing {
    func isAuthorized() -> Bool {
        AXIsProcessTrusted()
    }

    func requestAuthorization() {
        // Best effort in-process prompt. App Sandbox usually suppresses this,
        // but it is harmless and correct if the app is ever unsandboxed.
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        // Reliable prompt channel: the unsandboxed helper surfaces the system
        // dialog that App Sandbox suppresses here. The grant is attributed to
        // this app, which is what `isAuthorized()` reads.
        XPCHelperClient.shared.requestAccessibilityAuthorization()

        // Deterministic fallback: open the exact pane so a stale (for example
        // ad-hoc-signature) entry can always be reviewed or re-granted.
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) {
            NSWorkspace.shared.open(url)
        }
    }
}