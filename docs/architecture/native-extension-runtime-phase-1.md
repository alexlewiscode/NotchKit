# Native extension runtime Phase 1 findings

- Status: Feasibility proven for macOS 26; production integration not started
- Date: 2026-09-17
- Branch: `prototype/native-extension-runtime-phase-1`
- Base commit: `1f90af7`
- Prototype: [`Prototype/native-extension-runtime/`](../../Prototype/native-extension-runtime/)

## Decision Supported By This Prototype

Tier B can use ExtensionKit remote UI on macOS 26 and newer while NotchKit keeps
its macOS 14 deployment target and existing Tier A runtime. A Tier B provider is
installed independently, remains disabled until the user approves it in the
system browser, runs outside the host process, and owns its SwiftUI hierarchy.
The host receives an opaque remote scene and exchanges only bounded `Data` over
an Objective-C XPC protocol.

This result removes the technical-feasibility block. It does not approve a
production rollout: Developer ID signing, notarization, archive transport,
update policy, marketplace review, and integration with the macOS 14 host still
need separate work.

## Implemented Architecture

| Layer | Implementation |
| --- | --- |
| Extension point | Host `@AppExtensionPoint.Definition`; extension `@AppExtensionPoint.Bind`; generated `.appexpt` |
| Discovery | `AppExtensionPoint.Monitor` exposes only enabled identities |
| Consent | `EXAppExtensionBrowserViewController` system enable/disable UI |
| Remote UI | `EXHostViewController` configured with identity and scene `main` |
| Extension scene | `PrimitiveAppExtensionScene` owns the Pomodoro SwiftUI view |
| Control channel | `NSXPCConnection` with an `@objc` service and bounded JSON `Data` |
| Lifecycle | Activation/deactivation delegates, interruption and invalidation handlers, generation checks |
| Distribution unit | Signed provider app with a signed extension under `Contents/Extensions` |
| Package envelope | Extracted `.notchkitextension` directory with manifest, signature metadata, payload, and resources |

The provider bundle identifier contains the extension identifier as required by
Apple's embedded-binary validation. Host, provider, and extension use sandbox and
hardened-runtime settings. Signing-team selection is supplied externally and is
not committed to the Xcode project.

## Observed Acceptance Results

All observations below used macOS 26.5, Xcode 26.6, and Apple Development
signing in a GUI user session.

| Gate | Result | Evidence |
| --- | --- | --- |
| Independent install | Pass | Provider installed under `~/Applications/NotchKit Extensions`, outside the host bundle |
| Default approval flow | Pass | System browser listed Pomodoro and required user enablement |
| Discovery | Pass | Monitor listed the enabled installed extension; stale build registrations were removed before observation |
| Remote SwiftUI | Pass | Pomodoro timer rendered in the host and accepted interaction |
| Handshake | Pass | Host reached `Active` only after protocol/version/identity validation |
| Process isolation | Pass | Host and extension had distinct PIDs and executable bundle paths |
| Crash containment | Pass | Test exit terminated the extension; host stayed alive and reported interruption |
| Relaunch recovery | Pass | Relaunching the host created a new extension PID, scene, and active XPC session |
| Disable teardown | Pass | Disabling removed discovery identity and, after a stale-selection fix, dismantled the remote view |
| Re-enable | Pass | Re-enabling was observed by the monitor and restored the timer without host relaunch |
| Uninstall | Pass | Registration and installed files were removed; uninstall now terminates processes from the exact install path |
| Automated contract tests | Pass | 16 Swift tests, 0 failures |
| Product verification | Pass | Host point, nested extension, entitlements, and code signatures verified |

## Findings From Live Exercise

1. Xcode builds register their output with LaunchServices, which can create
   duplicate identities during development. Acceptance testing must unregister
   build-directory copies and prove discovery from the installed provider path.
2. Removing an identity from discovery is not sufficient by itself. The host
   must reconcile its selected identity and explicitly dismantle the remote view
   when an extension is disabled or removed.
3. A crash probe hidden behind an undefined custom `DEBUG` condition can become
   a silent no-op in a hand-authored project. Prototype diagnostics must be
   verified against the produced binary and observed process exit.
4. Unregistering and deleting an app does not terminate already-running
   executables. The local uninstall helper stops only processes whose full
   command path belongs to the installed provider before removing it.
5. An interrupted XPC connection is not reusable. The current prototype proves
   reconnection through a fresh host scene/relaunch, not automatic in-place
   restart.

## Remaining Gates

- Build and validate Developer ID signed provider and extension products.
- Notarize and staple the distributable artifact, then exercise Gatekeeper on a
  clean Mac/user account.
- Define a compressed archive format with extraction limits and path-traversal
  defenses, or explicitly standardize the directory package as the transport.
- Add publisher/team allow-list policy, revocation behavior, update semantics,
  and marketplace validation.
- Decide whether automatic crash restart is desirable; if so, add bounded
  backoff and crash-loop suppression.
- Integrate through an availability-gated Tier B adapter without introducing
  ExtensionKit references into macOS 14 execution paths.

## Conclusion

The macOS 26 ExtensionKit route is technically viable for Tier B and satisfies
the Phase 1 isolation and UX goals. Tier A remains the production runtime and
the product continues to support macOS 14. Distribution hardening, not remote UI
feasibility, is now the primary blocker.
