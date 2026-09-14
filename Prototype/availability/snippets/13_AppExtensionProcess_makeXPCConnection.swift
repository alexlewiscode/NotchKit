import Foundation
import ExtensionFoundation

func availabilityCheck(_ value: AppExtensionProcess) throws -> NSXPCConnection {
    try value.makeXPCConnection()
}