import Foundation
import ExtensionFoundation

func availabilityCheck<T: AppExtensionConfiguration>(_ value: T) -> Bool {
    value.accept(connection: NSXPCConnection(serviceName: "check"))
}