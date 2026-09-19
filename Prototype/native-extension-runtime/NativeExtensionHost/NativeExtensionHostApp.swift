import ExtensionFoundation
import SwiftUI

extension AppExtensionPoint {
    @Definition
    static var notchKitNativeUI: AppExtensionPoint {
        Name("native-ui")
        UserInterface(true)
        Scope(restriction: .none)
    }
}

@main
struct NativeExtensionHostApp: App {
    var body: some Scene {
        WindowGroup {
            HostContentView()
                .frame(minWidth: 860, minHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
