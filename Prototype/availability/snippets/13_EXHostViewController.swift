import AppKit
import ExtensionFoundation
import ExtensionKit

@MainActor
func availabilityCheck(_ identity: AppExtensionIdentity) {
    let vc = EXHostViewController()
    vc.configuration = EXHostViewController.Configuration(appExtension: identity, sceneID: "main")
}