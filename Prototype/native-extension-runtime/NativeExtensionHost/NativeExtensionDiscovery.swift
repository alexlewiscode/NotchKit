import ExtensionFoundation
import Foundation
import Observation

@MainActor
@Observable
final class NativeExtensionDiscovery {
    private(set) var monitor: AppExtensionPoint.Monitor?
    private(set) var errorMessage: String?
    private(set) var generation = 0

    var identities: [AppExtensionIdentity] {
        monitor?.identities.sorted { $0.localizedName < $1.localizedName } ?? []
    }

    var unapprovedCount: Int {
        monitor?.state.unapprovedCount ?? 0
    }

    var disabledCount: Int {
        monitor?.state.disabledCount ?? 0
    }

    func start() async {
        do {
            monitor = try await AppExtensionPoint.Monitor(appExtensionPoint: .notchKitNativeUI)
            errorMessage = nil
            generation &+= 1
        } catch {
            monitor = nil
            errorMessage = error.localizedDescription
        }
    }
}
