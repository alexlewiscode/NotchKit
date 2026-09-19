import ExtensionFoundation

@available(macOS 26.0, *)
extension AppExtensionPoint {
    @Definition
    static var notchKitNativeUI: AppExtensionPoint {
        Name("native-ui")
        UserInterface(true)
        Scope(restriction: .none)
    }
}
