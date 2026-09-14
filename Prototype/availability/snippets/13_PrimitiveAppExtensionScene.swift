import SwiftUI
import ExtensionKit

@MainActor
func availabilityCheck() -> PrimitiveAppExtensionScene {
    PrimitiveAppExtensionScene(id: "main") { Text("hello") }
}