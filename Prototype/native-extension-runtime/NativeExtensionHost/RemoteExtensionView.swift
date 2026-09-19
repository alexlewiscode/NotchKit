import AppKit
import ExtensionFoundation
import ExtensionKit
import SwiftUI

struct RemoteExtensionView: NSViewControllerRepresentable {
    let identity: AppExtensionIdentity
    let extensionID: String
    let sceneID: String
    let session: RemoteExtensionSession

    func makeCoordinator() -> Coordinator {
        Coordinator(identity: identity, extensionID: extensionID, session: session)
    }

    func makeNSViewController(context: Context) -> EXHostViewController {
        session.beginActivation()
        let controller = EXHostViewController()
        controller.delegate = context.coordinator
        controller.placeholderView = NSHostingView(
            rootView: ProgressView("Starting \(identity.localizedName)...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
        controller.configuration = .init(appExtension: identity, sceneID: sceneID)
        return controller
    }

    func updateNSViewController(_ controller: EXHostViewController, context: Context) {
        let configuration = controller.configuration
        guard configuration?.appExtension != identity || configuration?.sceneID != sceneID else {
            return
        }
        session.beginActivation()
        context.coordinator.identity = identity
        context.coordinator.extensionID = extensionID
        controller.configuration = .init(appExtension: identity, sceneID: sceneID)
    }

    static func dismantleNSViewController(_ controller: EXHostViewController, coordinator: Coordinator) {
        controller.configuration = nil
        coordinator.session.deactivate()
    }

    @MainActor
    final class Coordinator: NSObject, EXHostViewControllerDelegate {
        var identity: AppExtensionIdentity
        var extensionID: String
        let session: RemoteExtensionSession

        init(
            identity: AppExtensionIdentity,
            extensionID: String,
            session: RemoteExtensionSession
        ) {
            self.identity = identity
            self.extensionID = extensionID
            self.session = session
        }

        func hostViewControllerDidActivate(_ viewController: EXHostViewController) {
            session.didActivate(
                viewController,
                identity: identity,
                extensionID: extensionID,
                sceneID: "main"
            )
        }

        func hostViewControllerWillDeactivate(
            _ viewController: EXHostViewController,
            error: (any Error)?
        ) {
            session.didDeactivate(error: error)
        }
    }
}
