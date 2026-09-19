import NotchExtensionSDK
import NotchExtensionWire
import NotchNativeExtensionRuntime
import SwiftUI

@available(macOS 26.0, *)
struct DeclarativeExtensionView: View {
    let session: NativeDeclarativeExtensionSession
    let assetsURL: URL?

    @State private var tree: DeclarativeUITree?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading extension...")
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Extension Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Retry") { Task { await load(restart: true) } }
                }
            } else if let tree {
                node(tree.root)
            }
        }
        .task { await load(restart: true) }
        .onDisappear { session.teardown() }
    }

    private func node(_ node: DeclarativeUINode) -> AnyView {
        let rendered: AnyView
        switch node.component {
        case .text(let text):
            rendered = AnyView(Text(text))
        case .symbol(let systemName):
            rendered = AnyView(Image(systemName: systemName))
        case .image(let resourceName):
            if let image = LocalExtensionAssetLoader.image(
                named: resourceName,
                assetsRoot: assetsURL
            ) {
                rendered = AnyView(Image(nsImage: image))
            } else {
                rendered = AnyView(
                    Label("Image unavailable", systemImage: "photo.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                )
            }
        case .spacer(let minLength):
            rendered = AnyView(Spacer(minLength: minLength.map { CGFloat($0) }))
        case .divider:
            rendered = AnyView(Divider())
        case .progress(let value):
            rendered = value.map { AnyView(ProgressView(value: $0)) } ?? AnyView(ProgressView())
        case .hStack(let spacing, let children):
            rendered = AnyView(HStack(spacing: spacing.map { CGFloat($0) }) {
                ForEach(children) { child in self.node(child) }
            })
        case .vStack(let spacing, let children):
            rendered = AnyView(VStack(spacing: spacing.map { CGFloat($0) }) {
                ForEach(children) { child in self.node(child) }
            })
        case .button(let actionID, let label):
            rendered = AnyView(Button {
                Task { await perform(nodeID: node.id, actionID: actionID) }
            } label: {
                self.node(label)
            })
        case .toggle(let actionID, let isOn, let label):
            rendered = AnyView(Toggle(isOn: Binding(
                get: { isOn },
                set: { value in
                    Task { await perform(nodeID: node.id, actionID: actionID, value: .bool(value)) }
                }
            )) {
                self.node(label)
            })
        }
        return AnyView(rendered.modifier(
            DeclarativeAccessibilityModifier(accessibility: node.accessibility)
        ))
    }

    private func load(restart: Bool) async {
        isLoading = true
        errorMessage = nil
        do {
            if restart { try await session.start() }
            let rendered = try await session.fetchRender()
            try DeclarativeUIValidator.validate(rendered)
            tree = rendered
        } catch {
            tree = nil
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func perform(nodeID: String, actionID: String, value: ExtensionActionValue? = nil) async {
        do {
            let response = try await session.performAction(nodeID: nodeID, actionID: actionID, value: value)
            guard response.accepted else {
                throw NativeExtensionSessionError.remoteFailure(
                    response.failure ?? .init(code: "rejected", message: "The extension rejected the action.")
                )
            }
            if response.needsRender { await load(restart: false) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@available(macOS 26.0, *)
private struct DeclarativeAccessibilityModifier: ViewModifier {
    let accessibility: DeclarativeAccessibility?

    func body(content: Content) -> some View {
        content
            .modifier(OptionalAccessibilityLabel(value: accessibility?.label))
            .modifier(OptionalAccessibilityHint(value: accessibility?.hint))
            .modifier(OptionalAccessibilityValue(value: accessibility?.value))
            .modifier(OptionalAccessibilityHidden(value: accessibility?.hidden))
    }
}

@available(macOS 26.0, *)
private struct OptionalAccessibilityLabel: ViewModifier {
    let value: String?
    @ViewBuilder func body(content: Content) -> some View {
        if let value { content.accessibilityLabel(Text(value)) } else { content }
    }
}

@available(macOS 26.0, *)
private struct OptionalAccessibilityHint: ViewModifier {
    let value: String?
    @ViewBuilder func body(content: Content) -> some View {
        if let value { content.accessibilityHint(Text(value)) } else { content }
    }
}

@available(macOS 26.0, *)
private struct OptionalAccessibilityValue: ViewModifier {
    let value: String?
    @ViewBuilder func body(content: Content) -> some View {
        if let value { content.accessibilityValue(Text(value)) } else { content }
    }
}

@available(macOS 26.0, *)
private struct OptionalAccessibilityHidden: ViewModifier {
    let value: Bool?
    @ViewBuilder func body(content: Content) -> some View {
        if let value { content.accessibilityHidden(value) } else { content }
    }
}
