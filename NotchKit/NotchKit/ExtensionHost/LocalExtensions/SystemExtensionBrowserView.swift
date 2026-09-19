import ExtensionKit
import SwiftUI

@available(macOS 26.0, *)
struct SystemExtensionBrowserView: NSViewControllerRepresentable {
    func makeNSViewController(context: Context) -> EXAppExtensionBrowserViewController {
        EXAppExtensionBrowserViewController()
    }

    func updateNSViewController(
        _ nsViewController: EXAppExtensionBrowserViewController,
        context: Context
    ) {}
}
