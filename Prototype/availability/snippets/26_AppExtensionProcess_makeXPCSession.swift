import ExtensionFoundation
import XPC

func availabilityCheck(_ value: AppExtensionProcess) throws -> XPCSession {
    try value.makeXPCSession()
}