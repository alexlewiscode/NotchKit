import Foundation
import ExtensionFoundation

@MainActor
func availabilityCheck() -> ConnectionHandler {
    ConnectionHandler(onConnection: { _ in false })
}