import Foundation
import NotchExtensionSDK
import NotchExtensionWire

final class PomodoroExtensionService: NSObject, NotchExtensionServiceProtocol {
    static let shared = PomodoroExtensionService()

    private static let extensionID = try! ExtensionIdentity("com.notchkit.samples.pomodoro")
    private static let extensionVersion = ExtensionVersion(major: 1, minor: 0, patch: 0)
    private static let entryPointIDs: Set<String> = ["main", "compact", "closed"]
    private static let declarativeEntryPointIDs: Set<String> = ["compact", "closed"]
    private static let focusDuration: TimeInterval = 25 * 60

    private let lock = NSLock()
    private var remaining = focusDuration
    private var endDate: Date?

    func handshake(_ requestData: Data, withReply reply: @escaping (Data) -> Void) {
        let request: ExtensionHandshakeRequest
        do {
            request = try ExtensionWireCodec.decode(ExtensionHandshakeRequest.self, from: requestData)
            try ExtensionWireValidator.validate(
                request,
                expectedExtensionID: Self.extensionID,
                entryPointIDs: Self.entryPointIDs,
                supportedProtocolVersions: .init(minimum: 1, maximum: 1)
            )
        } catch {
            reply(handshakeFailure(for: try? ExtensionWireCodec.decode(ExtensionHandshakeRequest.self, from: requestData), error: error))
            return
        }

        reply(encoded(ExtensionHandshakeResponse(
            requestID: request.requestID,
            protocolVersion: request.protocolVersion,
            extensionID: Self.extensionID,
            entryPointID: request.entryPointID,
            extensionVersion: Self.extensionVersion,
            accepted: true
        )))
    }

    func render(_ requestData: Data, withReply reply: @escaping (Data) -> Void) {
        let request: ExtensionRenderRequest
        do {
            request = try ExtensionWireCodec.decode(ExtensionRenderRequest.self, from: requestData)
            try ExtensionWireValidator.validate(
                request,
                expectedExtensionID: Self.extensionID,
                entryPointIDs: Self.declarativeEntryPointIDs
            )
            let tree = makeTree(for: request.entryPointID)
            try DeclarativeUIValidator.validate(tree)
            reply(encoded(ExtensionRenderResponse(requestID: request.requestID, tree: tree)))
        } catch {
            let requestID = (try? ExtensionWireCodec.decode(ExtensionRenderRequest.self, from: requestData).requestID) ?? UUID()
            reply(encoded(ExtensionRenderResponse(
                requestID: requestID,
                failure: .init(code: "invalid-render-request", message: String(describing: error))
            )))
        }
    }

    func performAction(_ requestData: Data, withReply reply: @escaping (Data) -> Void) {
        let request: ExtensionActionRequest
        do {
            request = try ExtensionWireCodec.decode(ExtensionActionRequest.self, from: requestData)
            try ExtensionWireValidator.validate(
                request,
                expectedExtensionID: Self.extensionID,
                entryPointIDs: Self.declarativeEntryPointIDs
            )
        } catch {
            let requestID = (try? ExtensionWireCodec.decode(ExtensionActionRequest.self, from: requestData).requestID) ?? UUID()
            reply(encoded(ExtensionActionResponse(
                requestID: requestID,
                accepted: false,
                failure: .init(code: "invalid-action-request", message: String(describing: error))
            )))
            return
        }

        let response: ExtensionActionResponse
        switch (request.nodeID, request.actionID) {
        case ("start-button", "start"), ("closed-toggle", "start"):
            start()
            response = .init(requestID: request.requestID, accepted: true, needsRender: true)
        case ("pause-button", "pause"), ("closed-toggle", "pause"):
            pause()
            response = .init(requestID: request.requestID, accepted: true, needsRender: true)
        case ("reset-button", "reset"):
            reset()
            response = .init(requestID: request.requestID, accepted: true, needsRender: true)
        case ("open-button", "open-full"):
            response = .init(
                requestID: request.requestID,
                accepted: true,
                hostAction: .openDestination(entryPointID: "main")
            )
        default:
            response = .init(
                requestID: request.requestID,
                accepted: false,
                failure: .init(code: "unknown-action", message: "The requested control or action is not declared.")
            )
        }
        reply(encoded(response))
    }

    private func makeTree(for entryPointID: String) -> DeclarativeUITree {
        let snapshot = timerSnapshot()
        return entryPointID == "closed" ? closedTree(snapshot) : compactTree(snapshot)
    }

    private func compactTree(_ snapshot: TimerSnapshot) -> DeclarativeUITree {
        DeclarativeUITree(root: .init(
            id: "compact-root",
            component: .vStack(spacing: 10, children: [
                .init(id: "compact-heading", component: .hStack(spacing: 7, children: [
                    .init(
                        id: "compact-symbol",
                        component: .symbol(systemName: "timer"),
                        accessibility: .init(label: "Focus timer")
                    ),
                    .init(id: "compact-title", component: .text(snapshot.running ? "Focus in progress" : "Ready to focus")),
                    .init(id: "compact-spacer", component: .spacer(minLength: 4))
                ])),
                .init(
                    id: "compact-time",
                    component: .text(snapshot.formatted),
                    accessibility: .init(label: "Time remaining", value: snapshot.formatted)
                ),
                .init(
                    id: "compact-progress",
                    component: .progress(value: snapshot.remaining / Self.focusDuration),
                    accessibility: .init(label: "Focus session progress", value: snapshot.formatted + " remaining")
                ),
                .init(id: "compact-controls", component: .hStack(spacing: 8, children: [
                    button(id: "start-button", action: "start", title: "Start"),
                    button(id: "pause-button", action: "pause", title: "Pause"),
                    button(id: "reset-button", action: "reset", title: "Reset")
                ]))
            ]),
            accessibility: .init(label: "Pomodoro focus controls", value: snapshot.formatted + " remaining")
        ))
    }

    private func closedTree(_ snapshot: TimerSnapshot) -> DeclarativeUITree {
        DeclarativeUITree(root: .init(
            id: "closed-root",
            component: .hStack(spacing: 8, children: [
                .init(
                    id: "closed-symbol",
                    component: .symbol(systemName: snapshot.running ? "timer.circle.fill" : "timer.circle"),
                    accessibility: .init(label: snapshot.running ? "Focus timer running" : "Focus timer paused")
                ),
                .init(
                    id: "closed-time",
                    component: .text(snapshot.formatted),
                    accessibility: .init(label: "Time remaining", value: snapshot.formatted)
                ),
                .init(
                    id: "closed-toggle",
                    component: .toggle(
                        actionID: snapshot.running ? "pause" : "start",
                        isOn: snapshot.running,
                        label: .init(id: "closed-toggle-label", component: .text(snapshot.running ? "Pause" : "Start"))
                    ),
                    accessibility: .init(label: snapshot.running ? "Pause focus timer" : "Start focus timer")
                ),
                button(id: "open-button", action: "open-full", title: "Open")
            ]),
            accessibility: .init(label: "Pomodoro", value: snapshot.formatted + " remaining")
        ))
    }

    private func button(id: String, action: String, title: String) -> DeclarativeUINode {
        .init(
            id: id,
            component: .button(
                actionID: action,
                label: .init(id: id + "-label", component: .text(title))
            ),
            accessibility: .init(label: title + " focus timer")
        )
    }

    private func timerSnapshot() -> TimerSnapshot {
        lock.lock()
        defer { lock.unlock() }
        if let endDate, endDate <= Date() {
            remaining = 0
            self.endDate = nil
        }
        let value = endDate.map { max(0, $0.timeIntervalSinceNow) } ?? remaining
        return TimerSnapshot(remaining: value, running: endDate != nil)
    }

    private func start() {
        lock.lock()
        defer { lock.unlock() }
        guard endDate == nil else { return }
        if remaining <= 0 { remaining = Self.focusDuration }
        endDate = Date().addingTimeInterval(remaining)
    }

    private func pause() {
        lock.lock()
        defer { lock.unlock() }
        guard let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        self.endDate = nil
    }

    private func reset() {
        lock.lock()
        defer { lock.unlock() }
        remaining = Self.focusDuration
        endDate = nil
    }

    private func handshakeFailure(for request: ExtensionHandshakeRequest?, error: Error) -> Data {
        encoded(ExtensionHandshakeResponse(
            requestID: request?.requestID ?? UUID(),
            protocolVersion: ExtensionWireProtocol.currentVersion,
            extensionID: Self.extensionID,
            entryPointID: request?.entryPointID ?? "invalid",
            extensionVersion: Self.extensionVersion,
            accepted: false,
            failure: .init(code: "handshake-rejected", message: String(describing: error))
        ))
    }

    private func encoded<T: Encodable>(_ value: T) -> Data {
        (try? ExtensionWireCodec.encode(value)) ?? Data()
    }
}

private struct TimerSnapshot {
    let remaining: TimeInterval
    let running: Bool

    var formatted: String {
        let total = max(0, Int(remaining.rounded(.up)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
