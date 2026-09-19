import ExtensionFoundation
import Observation

@available(macOS 26.0, *)
@MainActor
@Observable
public final class NativeExtensionMonitor {
    public let appExtensionPoint: AppExtensionPoint
    public private(set) var monitor: AppExtensionPoint.Monitor?
    public private(set) var lastError: Error?

    public var identities: [AppExtensionIdentity] {
        (monitor?.identities ?? []).sorted {
            if $0.localizedName == $1.localizedName { return $0.bundleIdentifier < $1.bundleIdentifier }
            return $0.localizedName.localizedStandardCompare($1.localizedName) == .orderedAscending
        }
    }

    public var disabledCount: Int { monitor?.state.disabledCount ?? 0 }
    public var unapprovedCount: Int { monitor?.state.unapprovedCount ?? 0 }

    public init(appExtensionPoint: AppExtensionPoint) {
        self.appExtensionPoint = appExtensionPoint
    }

    public func start() async throws {
        do {
            monitor = try await AppExtensionPoint.Monitor(appExtensionPoint: appExtensionPoint)
            lastError = nil
        } catch {
            monitor = nil
            lastError = error
            throw error
        }
    }

    public func stop() {
        monitor = nil
        lastError = nil
    }
}
