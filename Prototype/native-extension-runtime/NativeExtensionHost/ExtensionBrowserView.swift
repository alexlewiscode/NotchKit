import ExtensionKit
import SwiftUI

struct ExtensionBrowserView: NSViewControllerRepresentable {
    func makeNSViewController(context: Context) -> EXAppExtensionBrowserViewController {
        EXAppExtensionBrowserViewController()
    }

    func updateNSViewController(
        _ nsViewController: EXAppExtensionBrowserViewController,
        context: Context
    ) {}
}
