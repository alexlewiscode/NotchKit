import Foundation
import ExtensionFoundation

// Host-defined contract (in a real app this lives in a shared framework).
protocol NotchKitPrototypeExtension: AppExtension {}

struct NotchKitPrototypeConfiguration<E: NotchKitPrototypeExtension>: AppExtensionConfiguration {
    let appExtension: E

    func accept(connection: NSXPCConnection) -> Bool {
        // A real extension would configure the connection here.
        return true
    }
}

extension NotchKitPrototypeExtension {
    var configuration: NotchKitPrototypeConfiguration<some NotchKitPrototypeExtension> {
        NotchKitPrototypeConfiguration(appExtension: self)
    }
}

@main
final class NotchKitPrototypeExtensionMain: NotchKitPrototypeExtension {
    required init() {}
}