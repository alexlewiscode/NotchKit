# Extension runtime prototype: out-of-process evidence on the macOS 14 target

- Status: Prototype evidence (bounded, isolated branch `prototype/extension-runtime`)
- Date: 2026-09-15
- Base commit: `fe8de9c`
- Scope: compile-time availability, XPC wire contract, bundled helper, ExtensionKit path, lifecycle observability
- Prototype sources: [`Prototype/`](../../Prototype/)

This report records what was **run and observed**, what was **built but not run**,
and what remains **unverified**, on the macOS 14 deployment target. It does not
change the production runtime: the app stays on the in-process, first-party
Tier A runtime (ADR 0001/0002).

## Environment

| Item | Value |
| --- | --- |
| Host OS | macOS 26.5 (build 25F71), arm64 |
| Xcode | 26.6 (17F113), `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` |
| SDK | `MacOSX26.5.sdk` |
| Compiler | Apple Swift 6.3.3 (swiftlang-6.3.3.1.3) |
| Signing | ad-hoc (`codesign -s -`) only; no Developer ID, no team, no notarization |
| Headless | yes (no GUI, no enable-extension prompts) |

## Bottom line up front

1. **All availability claims in ADR 0002 are compiler-verified** at
   `-target arm64-apple-macos14.0`. The `AppExtensionPoint` / `ConnectionHandler`
   / `makeXPCSession()` surface is macOS **26.0+**; the ExtensionFoundation
   process/connection surface and the ExtensionKit host/UI surface are macOS
   **13.0+**; `XPC.XPCSession`/`XPCPeerHandler` are macOS **14.0+**.
2. **A `Codable` value is not an XPC wire argument.** This was proven twice: a
   compile failure when a Swift struct is used as an `@objc` protocol parameter,
   and a real, observed NSXPC round trip that carries JSON `Data` instead.
3. **An embedded XPC helper (bundled, ad-hoc signed) runs headlessly** and yields
   observed launch/interruption/invalidation lifecycle. It is **not** an
   independently installed extension and does not demonstrate installation.
4. **The ExtensionKit discovery path is blocked headlessly.** `AppExtensionIdentity.matching`
   failed with `com.apple.extensionKit.errorDomain` code 13 even with an embedded
   `.appex` and a hand-authored extension-point file. Discovery/enablement needs
   a real signing identity and/or a system enablement UI, and on macOS 14 the
   programmatic extension-point mechanism is unavailable.
5. **Do not switch the production app.** The evidence needed before choosing
   ExtensionKit is not obtainable in this headless, unsigned environment (see
   [What would be needed](#what-evidence-is-needed-before-choosing-extensionkit-vs-isolated-xpc)).

---

## 1. Compile-time availability verification

### Method

Each symbol was exercised by a tiny standalone Swift file in
[`Prototype/availability/snippets/`](../../Prototype/availability/snippets/).
Each file was type-checked twice:

```
xcrun swiftc -target arm64-apple-macos14.0 -typecheck <snippet> -sdk $(xcrun --show-sdk-path --sdk macosx)
xcrun swiftc -target arm64-apple-macos26.0 -typecheck <snippet> -sdk $(xcrun --show-sdk-path --sdk macosx)
```

A snippet that fails at 14.0 **and succeeds at 26.0** proves a deployment-target
availability gate (not a general API error). Runner:
[`run-availability.sh`](../../Prototype/availability/run-availability.sh);
machine-readable results:
[`availability-results.tsv`](../../Prototype/availability/availability-results.tsv);
full diagnostics: [`logs/`](../../Prototype/availability/logs/).

### Results

`exit=0` means the compiler accepted the reference at that deployment target.

| Symbol | Verified availability | macOS 14 typecheck | Evidence / command |
| --- | --- | --- | --- |
| `AppExtension` | 13.0+ | pass | `13_AppExtension.swift` |
| `AppExtensionConfiguration` (+ `accept(connection:)`) | 13.0+ | pass | `13_AppExtensionConfiguration.swift` |
| `AppExtensionIdentity` | 13.0+ | pass | `13_AppExtensionIdentity.swift` |
| `AppExtensionProcess` | 13.0+ | pass | `13_AppExtensionProcess.swift` |
| `AppExtensionProcess.invalidate()` | 13.0+ | pass | `13_AppExtensionProcess_invalidate.swift` |
| `AppExtensionProcess.makeXPCConnection()` | 13.0+ | pass | `13_AppExtensionProcess_makeXPCConnection.swift` |
| `AppExtensionProcess.Configuration.onInterruption` | 13.0+ | pass | `13_AppExtensionProcess_Configuration_onInterruption.swift` |
| `EXHostViewController` | 13.0+ | pass | `13_EXHostViewController.swift` |
| `EXHostViewController.Configuration` (`appExtension`/`sceneID`) | 13.0+ | pass | `13_EXHostViewController.swift` |
| `EXHostViewControllerDelegate` | 13.0+ | pass | `13_EXHostViewControllerDelegate.swift` |
| `EXAppExtensionBrowserViewController` | 13.0+ | pass | `13_EXAppExtensionBrowserViewController.swift` |
| `PrimitiveAppExtensionScene` | 13.0+ | pass | `13_PrimitiveAppExtensionScene.swift` |
| `AppExtensionScene` | 13.0+ | pass | `13_AppExtensionScene.swift` |
| `XPC.XPCSession` | 14.0+ | pass | `14_XPCSession.swift` |
| `XPC.XPCPeerHandler` | 14.0+ | pass | `14_XPCPeerHandler.swift` |
| `AppExtensionPoint` | **26.0+** | fail | `26_AppExtensionPoint.swift` |
| `AppExtensionPoint.Definition` | **26.0+** | fail | `26_AppExtensionPoint_Definition.swift` |
| `AppExtensionPoint.Name` | **26.0+** | fail | `26_AppExtensionPoint_Name.swift` |
| `AppExtensionPoint.UserInterface` | **26.0+** | fail | `26_AppExtensionPoint_UserInterface.swift` |
| `AppExtensionPoint.Scope` | **26.0+** | fail | `26_AppExtensionPoint_Scope.swift` |
| `AppExtensionPoint.EnhancedSecurity` | **26.0+** | fail | `26_AppExtensionPoint_EnhancedSecurity.swift` |
| `AppExtensionPoint.Bind` | **26.0+** | fail | `26_AppExtensionPoint_Bind.swift` |
| `AppExtensionPoint.Monitor` | **26.0+** | fail | `26_AppExtensionPoint_Monitor.swift` |
| `ConnectionHandler` | **26.0+** | fail | `26_ConnectionHandler.swift` |
| `AppExtensionProcess.makeXPCSession()` | **26.0+** | fail | `26_AppExtensionProcess_makeXPCSession.swift` |

Every "fail" snippet compiles cleanly at `arm64-apple-macos26.0` (exit 0),
confirming the gate is the deployment target. Representative exact diagnostics:

```
26_AppExtensionProcess_makeXPCSession.swift:5:15: error: 'makeXPCSession()' is only available in macOS 26.0 or newer
    note: add 'if #available' version check

26_ConnectionHandler.swift:5:29: error: 'ConnectionHandler' is only available in macOS 26.0 or newer
    note: add '@available' attribute to enclosing global function
```

`AppExtensionPoint.*` snippets report the same shape:
`error: 'AppExtensionPoint' is only available in macOS 26.0 or newer`.

### SDK interface cross-check (ground truth)

The compiled evidence matches the SDK `.swiftinterface` annotations in
`MacOSX26.5.sdk`:

- `AppExtension` / `AppExtensionConfiguration`: `@available(macOS 13.0, ...)`
- `AppExtensionProcess`: `@available(macOS 13.0, ...)`; `makeXPCSession()` is
  separately annotated `@available(macOS 26.0, ...)`
- `AppExtensionPoint`, `ConnectionHandler`: `@available(macOS 26.0, ...)`
- `ExtensionKit`: `EXHostViewController` (+ Swift-overlay `Configuration`),
  `EXHostViewControllerDelegate`, `EXAppExtensionBrowserViewController`,
  `AppExtensionScene`/`PrimitiveAppExtensionScene`: macOS 13.0
- `XPC.swiftinterface`: `XPCSession`, `XPCPeerHandler`: `@available(macOS 14.0, ...)`

### One design finding from a naive snippet

A first attempt at a custom `AppExtensionScene` holding a SwiftUI `View` failed
at **both** 14 and 26 with `type 'Scene' does not conform to protocol
'AppExtensionScene'` / `'Body' = 'some View' ... can't conform to
'AppExtensionScene'` (see
`logs/13_AppExtensionScene.macos14.log`). A scene's `Body` must itself be an
`AppExtensionScene`; a `View` is only accepted at the `PrimitiveAppExtensionScene`
leaf. This corroborates ADR 0002's "opaque remote scene" UI model: the host never
sees view objects, only scene ids and data.

---

## 2. XPC wire contract (run and observed)

### 2.1 A real NSXPC round trip, headless

Source: [`Prototype/xpc-boundary/NsxpcRoundTrip.swift`](../../Prototype/xpc-boundary/NsxpcRoundTrip.swift).

An `NSXPCListener.anonymous()` + `NSXPCConnection(listenerEndpoint:)` pair gives a
genuine round trip with **no launchd registration, no bundle, no signing**. A
`Codable` value is JSON-encoded to `Data`, crosses, is decoded by the service,
mutated, re-encoded, and crosses back.

Observed output:

```
ROUND_TRIP_OK input=Greeting(text: "hello", count: 41) output=Greeting(text: "HELLO", count: 42)
run exit=0
```

This proves the transport carries the model **as `Data`**, not as a `Codable`
value.

### 2.2 Negative: a `Codable` struct cannot be an XPC argument

`Prototype/xpc-boundary/compile-fail/CodableStructAsXPCArgument.swift`:

```
error: instance method cannot be a member of an '@objc' protocol because the
type of the parameter 1 cannot be represented in Objective-C
```

### 2.3 Negative: a pure Swift protocol cannot build an `NSXPCInterface`

`Prototype/xpc-boundary/compile-fail/SwiftProtocolNotObjC.swift`:

```
error: cannot convert value of type '(any SwiftOnlyProtocol).Type' to expected
argument type 'Protocol'
```

### 2.4 What actually crosses (precise statement)

- `NSXPCInterface` is built from an **Objective-C `@objc` protocol**.
- The wire vocabulary is: property-list types (`NSData`, `NSString`, `NSNumber`,
  `NSDate`, `NSUUID`, `NSArray`, `NSDictionary`, …), collection element classes
  explicitly declared with `setClasses(_:for:argumentIndex:ofReply:)`, and
  **`NSSecureCoding`-conforming objects**. `NSXPCInterface`'s argument type is
  `Set<AnyHashable>`, so the `NSSecureCoding` constraint is a **runtime**
  requirement, not a compile-time one.
- **A `Codable` value crosses only when a transport encodes it.** Options:
  1. `NSXPCConnection` carrying `Data` / property lists (demonstrated, 13.0+ via
     ExtensionFoundation `accept(connection:)` + `makeXPCConnection()`).
  2. The XPC framework's `XPCSession`/`XPCPeerHandler`, whose messages are Swift
     `Encodable`/`Decodable` and are encoded by the framework. `XPCSession` is
     14.0+, but ExtensionFoundation's integration (`AppExtensionProcess.makeXPCSession()`,
     `ConnectionHandler`) is **26.0+**.
- **On macOS 14 the only ExtensionFoundation-supported contract is
  `NSXPCConnection`.** There is no supported `XPCSession` integration for app
  extensions below 26.0.
- SwiftUI `View` objects, closures, and arbitrary Swift structs have no Obj-C /
  property-list representation and cannot cross.

---

## 3. Bundled XPC helper prototype (built and run)

Source: [`Prototype/xpc-service/`](../../Prototype/xpc-service/). A minimal
`NotchKitPrototypeHost.app` with an embedded
`Contents/XPCServices/com.notchkit.prototype.xpcservice.xpc`, both ad-hoc signed.
Built manually (no Xcode project) at `arm64-apple-macos14.0`.

Observed:

```
== Attempt headless connection (direct exec of host binary) ==
HOST_XPC_OK reply=svc:host
host run exit=0

== Attempt headless connection via LaunchServices (open -W) ==
--- app stdout ---
HOST_XPC_OK reply=svc:host
```

Both a direct exec of the host binary inside the app bundle and a
LaunchServices `open` invocation connected to the embedded service and got a
reply. Ad-hoc signing via `codesign --force --deep --sign -` was sufficient for
this bundled path.

### 3.1 Existing repo helper also builds headlessly

The repository already contains a real `NotchKitXPCHelper` target/scheme. It was
built for the macOS 14 deployment target with no signing:

```
xcodebuild -project NotchKit/NotchKit.xcodeproj -scheme NotchKitXPCHelper \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
# compiler invocation contains: -target arm64-apple-macos14.0
** BUILD SUCCEEDED **
```

### 3.2 Bundled vs independently installed — plain statement

The helper above is **embedded inside the host app bundle** and is launched by
the host through `NSXPCConnection(serviceName:)`. It demonstrates
**out-of-process transport**, not independent installation. It does **not**
prove discovery, enablement, approval, or distribution of an artifact that lives
outside the host bundle. Independent installation remains unproven.

---

## 4. ExtensionKit path (attempted; blocked headlessly)

Source: [`Prototype/xcode-bundle/`](../../Prototype/xcode-bundle/). A hand-built
`NotchKitPrototypeDiscoveryHost.app` with an embedded
`Contents/PlugIns/com.notchkit.prototype.extension.appex` (11+ symbols only,
`arm64-apple-macos14.0`), plus a CLI using `AppExtensionIdentity.matching`.

### Observed

- Extension executable: build exit 0.
- Discovery host: build exit 0.
- Deep ad-hoc sign: exit 0.
- Discovery, direct exec **and** via `open`:

```
DISCOVERY_FAIL point=com.notchkit.prototype.point
  error=Error Domain=com.apple.extensionKit.errorDomain Code=13 "(null)"
```

- Hand-authoring an extension-point file at
  `Contents/ExtensionPoints/com.notchkit.prototype.point.appexpt` (format copied
  from `/System/Library/ExtensionKit/ExtensionPoints/*.appexpt`) did **not**
  change the error (still code 13).
- LaunchServices `open -W` also reported
  `Unable to block on application (GetProcessPID() returned 18446744073709551016)`,
  a headless limitation (no session to block against).

### Interpretation

`extensionKit.errorDomain` code 13 corresponds to the host not having a
registered/defined extension point. Apple documents that extension-point
definitions are collected **at installation time** from compiler-generated data
using the `EX_ENABLE_EXTENSION_POINT_GENERATION` build setting, and
`AppExtensionPoint` (the API to declare points) is **macOS 26.0+**. On macOS 14
there is no supported programmatic way for a third-party host to declare a
custom extension point. The hand-authored file was not sufficient in this
environment (unsigned, not installed, and/or the format/registration path is
26.0+).

### Manufactured `.appex`/`.appexpt` naming observed

On the test system: extension bundles are **`.appex`**
(`/System/Library/ExtensionKit/Extensions/*.appex`), and extension-point
definition files are **`.appexpt`**
(`/System/Library/ExtensionKit/ExtensionPoints/*.appexpt`, an Apple binary
plist). The `.appext` spelling used in earlier notes was not observed on disk; it
appears to conflate these two. This does not change the availability conclusion.

### What a real ExtensionKit run would require

- A **Development Team / Developer ID** signing identity (ad-hoc is insufficient
  for extension registration).
- A Generic Extension target (product type
  `com.apple.product-type.extensionkit-extension`; the older App Extension base
  uses `com.apple.product-type.app-extension`) built with a real team, and the
  extension embedded in the host.
- On macOS 26.x: `EX_ENABLE_EXTENSION_POINT_GENERATION=YES` on both host and
  extension, so the compiler writes point definitions/bindings into the bundle.
  On macOS 14: a hand-authored point definition plus whatever legacy
  registration Apple supported then (**not established by this prototype**).
- Sandbox/app-group entitlements for the extension
  (`com.apple.security.app-sandbox`, host/extension application groups, and for
  `EnhancedSecurity` points additional hardened-process entitlements observed on
  system extensions).
- **GUI enablement**: separately installed extensions are disabled by default and
  must be enabled through the system UI (`EXAppExtensionBrowserViewController`
  or System Settings), which cannot be driven headlessly.

---

## 5. Lifecycle observability

Source: [`Prototype/xpc-service/LifecycleHost.swift`](../../Prototype/xpc-service/LifecycleHost.swift)
over the embedded service. This observes the **`NSXPCConnection`** lifecycle,
which is the macOS 14 transport that `AppExtensionProcess` uses. It is **not**
an observation of `AppExtensionProcess` itself (which needs a discovered,
enabled extension identity).

Observed, in order:

```
LIFECYCLE_LAUNCH remote_pid=95547
LIFECYCLE_CRASH_REQUEST triggering remote crash
LIFECYCLE_INTERRUPTION (remote process crashed or connection interrupted)
LIFECYCLE_ERROR Error Domain=NSCocoaErrorDomain Code=4097 "connection to service named com.notchkit.prototype.xpcservice"
LIFECYCLE_AFTER_CRASH remote_pid=nil
LIFECYCLE_INVALIDATE_REQUEST calling invalidate()
LIFECYCLE_DONE
LIFECYCLE_INVALIDATION (connection invalidated)
```

| Phase | Documented | Observed headless |
| --- | --- | --- |
| Launch / out-of-process | Yes | **Yes** — remote PID distinct from host |
| Crash → interruption | `AppExtensionProcess.Configuration.onInterruption` (13.0+) | **Analogous** — `NSXPCConnection.interruptionHandler` fired; same connection then failed with `NSCocoaErrorDomain` 4097 and did not recover (`remote_pid=nil`); a new connection would be required |
| Explicit teardown | `AppExtensionProcess.invalidate()` (13.0+) | **Analogous** — `NSXPCConnection.invalidate()` fired `invalidationHandler` |
| Suspension / app-nap | Documented system behaviour, no host callback | **No** |
| `EXHostViewController` activation/deactivation | `hostViewControllerDidActivate:` / `hostViewControllerWillDeactivate:error:` (13.0+) | **No** — requires a GUI session and an enabled extension |
| Extension enable/disable discovery | `EXAppExtensionBrowserViewController`, Monitor (26.0+) | **No** — blocked (see §4) |

`AppExtensionProcess.onInterruption` and `.invalidate()` are compile-verified
(§1) but were **not executed**, because no discoverable/enabled extension exists
in this environment.

---

## 6. macOS compatibility and signing / entitlement requirements

| Path | macOS 14 status | Signing / entitlement requirement |
| --- | --- | --- |
| Bundled XPC service (`Contents/XPCServices/*.xpc`) | **Works**, observed | Ad-hoc (`codesign -s -`) sufficient to build and run headlessly; production would use Developer ID + hardened runtime |
| Anonymous-listener NSXPC round trip | **Works**, observed | None (no bundle, no launchd) |
| `NSXPCConnection` via ExtensionFoundation (`accept` + `makeXPCConnection`) | APIs compile at 13.0+, **not executed** | Real team + host/extension app groups; sandbox |
| ExtensionKit `.appex` discovery/enablement on macOS 14 | **Blocked**, observed error 13 | Real Development Team; hand-authored point definition; GUI enablement. No supported programmatic point declaration on 14 |
| ExtensionKit on macOS 26 | Not targeted by this prototype | `EX_ENABLE_EXTENSION_POINT_GENERATION=YES`; team; sandbox/app-groups |

No Developer ID identity is available here; **ad-hoc "Sign to Run Locally" is the
only signing available**, and it was enough only for the bundled helper and the
anonymous round trip.

---

## 7. What evidence is needed before choosing ExtensionKit vs isolated XPC

The production app **must stay on the in-process first-party Tier A runtime**
(ADR 0001/0002). The following are prerequisites before any switch, none of
which this environment can produce:

1. An **independently installed** (not embedded) artifact that the host
   discovers, lists, and enables — with observed default-disabled behavior —
   on macOS 14.
2. A runnable, observed `AppExtensionProcess` launch (`makeXPCConnection()` +
   `onInterruption` + `invalidate()`) against an enabled extension identity, not
   just a compile check.
3. A documented and working macOS 14 **hand-authored extension-point** mechanism
   (since `AppExtensionPoint` generation is 26.0+), verified by the system
   accepting and registering it.
4. Real **Developer ID signing and notarization** for host and extension,
   including the exact sandbox/app-group entitlement set.
5. Observed `EXHostViewController` activate/deactivate callbacks in a GUI session.

Until (1)–(5) exist, the only demonstrated out-of-process path is a bundled XPC
helper, which is a transport demo — not an extension-installation story. An XPC
adapter is additive over the current contracts; ExtensionKit cannot be chosen on
the strength of this prototype, and nothing here justifies moving the production
app off Tier A.

---

## 8. Reproduce

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# 1. Availability table (writes availability-results.tsv + logs/)
Prototype/availability/run-availability.sh

# 2. XPC boundary: real round trip + two compile-fail negatives
Prototype/xpc-boundary/run-boundary.sh

# 3. Bundled XPC helper: build, ad-hoc sign, run, lifecycle
Prototype/xpc-service/build-and-run.sh

# 4. ExtensionKit .appex discovery attempt (expected: error code 13)
Prototype/xcode-bundle/build-and-run.sh
```

Captured outputs:
[`xpc-boundary/observed-output.txt`](../../Prototype/xpc-boundary/observed-output.txt),
[`xpc-service/observed-output.txt`](../../Prototype/xpc-service/observed-output.txt),
[`xcode-bundle/observed-output.txt`](../../Prototype/xcode-bundle/observed-output.txt).

## 9. Corrections / confirmations to ADR 0002

- The ADR 0002 availability table is **confirmed by compiler** for every listed
  symbol. No availability correction is required.
- Terminology correction: observed on-disk artifacts are `.appex` (extensions)
  and `.appexpt` (extension points); earlier `.appext` wording was imprecise.
- The ADR's claim that a macOS 14 ExtensionKit path needs a hand-authored point
  definition is directionally supported (error 13 without a registered point),
  but this prototype could not get a hand-authored point accepted headlessly, so
  the exact macOS 14 registration mechanism remains unverified.

## UNVERIFIED items (explicit)

- Bundled helper ≠ independently installed extension; independent
  discovery/enablement/approval was not observed.
- `AppExtensionProcess` launch, `onInterruption`, and `invalidate()` were
  compile-verified but never executed against a real extension identity.
- `EXHostViewController` activation/deactivation delegate callbacks.
- Extension suspension / app-nap behavior.
- ExtensionKit discovery/enablement on macOS 14 (observed failure only).
- `.appex`/`.appexpt` registration requirements with a real signing team.
- Any GUI-driven flow (extension approval/enable, `open` on a headless session).
