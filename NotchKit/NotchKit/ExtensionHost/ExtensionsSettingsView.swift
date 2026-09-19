//
//  ExtensionsSettingsView.swift
//  NotchKit
//
//  The Extensions settings hub.
//
//  Lists first-party definitions from the authoritative `SettingsCatalog`. It
//  reads no contribution store settings and constructs no extension instance.
//  Every feature row exposes an authoritative enable/disable toggle on the
//  right; the row itself is a separate navigation target, so enabling a feature
//  never opens its configuration and opening configuration never changes
//  enablement.
//

import AppKit
import NotchExtensionInstallation
import NotchExtensionSDK
import NotchExtensionRuntime
import SwiftUI
import UniformTypeIdentifiers

/// The Extensions settings hub.
struct ExtensionsSettingsView: View {
    @ObservedObject private var catalog = NotchKitRuntime.shared.settingsCatalog
    @ObservedObject private var presentation = NotchKitRuntime.shared.presentation
    @ObservedObject private var localExtensions = NotchKitRuntime.shared.localExtensions

    /// Forwards a feature's "Keyboard Shortcuts" link to the root settings view.
    let onOpenShortcuts: (ShortcutsOwner) -> Void

    @State private var path: [ExtensionSettingsRoute] = []
    @State private var packagePreview: LocalExtensionPackagePreview?
    @State private var selectedLocalExtension: InstalledLocalExtension?
    @State private var pendingUninstall: InstalledLocalExtension?
    @State private var showsSystemExtensions = false
    @State private var localOperationError: String?

    private var runtime: NotchKitRuntime { .shared }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                homeSection
                localExtensionsSection

                Section {
                    if catalog.entries.isEmpty {
                        Text("No built-in features are available.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(catalog.entries) { entry in
                            FeatureSettingsRow(
                                entry: entry,
                                summary: metadata(for: entry)?.summary,
                                phase: phase(for: entry),
                                isEnabled: isEnabledBinding(for: entry),
                                onOpen: { destination in open(destination, in: entry) },
                                onRetry: { retry(entry) },
                                onGrantPermission: { grantPermission(entry) }
                            )
                        }
                    }
                } header: {
                    Text("Built-in features")
                } footer: {
                    Text(
                        "Turn a feature on or off with its switch, or open the row to configure it. "
                            + "Configuration stays available while a feature is off."
                    )
                }
            }
            .navigationTitle("Extensions")
            .accentColor(.effectiveAccent)
            .onExitCommand {
                if !path.isEmpty { path.removeLast() }
            }
            .toolbar {
                if !path.isEmpty {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            path.removeLast()
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .accessibilityLabel("Back to Extensions")
                    }
                }
            }
            .navigationDestination(for: ExtensionSettingsRoute.self) { route in
                destination(for: route, in: catalog.entry(for: route.destinationID))
            }
            .sheet(item: $packagePreview) { preview in
                LocalExtensionInstallConfirmation(
                    preview: preview,
                    onCancel: { packagePreview = nil },
                    onInstall: { install(preview) }
                )
            }
            .sheet(item: $selectedLocalExtension) { item in
                LocalExtensionDetailsView(item: item) {
                    selectedLocalExtension = nil
                    choosePackage(updating: item.id)
                }
            }
            .sheet(isPresented: $showsSystemExtensions) {
                if #available(macOS 26.0, *) {
                    SystemExtensionBrowserView()
                        .frame(minWidth: 620, minHeight: 480)
                }
            }
            .alert("Uninstall Local Extension?", isPresented: Binding(
                get: { pendingUninstall != nil },
                set: { if !$0 { pendingUninstall = nil } }
            )) {
                Button("Cancel", role: .cancel) { pendingUninstall = nil }
                Button("Uninstall", role: .destructive) {
                    guard let item = pendingUninstall else { return }
                    pendingUninstall = nil
                    Task { await uninstall(item) }
                }
            } message: {
                Text("This removes the managed provider application and all of its local contributions.")
            }
            .alert("Local Extension Error", isPresented: Binding(
                get: { localOperationError != nil || localExtensions.errorMessage != nil },
                set: { if !$0 { localOperationError = nil; localExtensions.clearError() } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(localOperationError ?? localExtensions.errorMessage ?? "Unknown error")
            }
        }
        .onChange(of: catalog.revision) { _, _ in
            let pruned = catalog.prune(path)
            if pruned != path { path = pruned }
        }
    }

    private var localExtensionsSection: some View {
        Section {
            if #available(macOS 26.0, *) {
                if localExtensions.installed.isEmpty {
                    Text("No local extensions are installed.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(localExtensions.installed) { item in
                        LocalExtensionRow(
                            item: item,
                            onSetEnabled: { localExtensions.setDesiredEnabled($0, for: item.id) },
                            onDetails: { selectedLocalExtension = item },
                            onRetry: { Task { await localExtensions.refresh() } },
                            onManage: { showsSystemExtensions = true },
                            onUpdate: { choosePackage(updating: item.id) },
                            onUninstall: { pendingUninstall = item }
                        )
                    }
                }
                HStack {
                    Button("Install Local Extension...") { choosePackage() }
                    Spacer()
                    Button("Manage System Extensions...") { showsSystemExtensions = true }
                    Button {
                        Task { await localExtensions.refresh() }
                    } label: {
                        if localExtensions.isRefreshing { ProgressView().controlSize(.small) }
                        else { Text("Refresh") }
                    }
                    .disabled(localExtensions.isRefreshing)
                }
            } else {
                Text("Local ExtensionKit extensions require macOS 26 or later.")
                    .foregroundStyle(.secondary)
                Button("Install Local Extension...") {}
                    .disabled(true)
            }
        } header: {
            Text("Installed local extensions")
        } footer: {
            if #available(macOS 26.0, *) {
                Text("The switch is your desired state. macOS approval and system enablement are shown separately.")
            }
        }
    }

    private func choosePackage(updating expectedID: ExtensionIdentity? = nil) {
        guard ensureManagedLocationAccess() else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose a NotchKit Extension"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "notchkitextension") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                var preview = try await LocalExtensionCoordinator.previewPackage(at: url)
                if let expectedID, preview.id != expectedID {
                    throw LocalExtensionSelectionError.updateIdentityMismatch
                }
                preview.isUpdate = localExtensions.installed.contains { $0.id == preview.id }
                packagePreview = preview
            } catch {
                localOperationError = error.localizedDescription
            }
        }
    }

    private func ensureManagedLocationAccess() -> Bool {
        guard !localExtensions.hasManagedLocationAccess else { return true }
        do {
            try FileManager.default.createDirectory(
                at: localExtensions.rootURL,
                withIntermediateDirectories: true
            )
            let panel = NSOpenPanel()
            panel.title = "Allow Local Extension Installation"
            panel.message = "Choose this LocalExtensions folder so NotchKit can install signed executable providers."
            panel.prompt = "Allow"
            panel.directoryURL = localExtensions.rootURL
            panel.allowsMultipleSelection = false
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = false
            guard panel.runModal() == .OK, let url = panel.url else { return false }
            try localExtensions.authorizeManagedLocation(at: url)
            return true
        } catch {
            localOperationError = error.localizedDescription
            return false
        }
    }

    private func install(_ preview: LocalExtensionPackagePreview) {
        packagePreview = nil
        Task {
            do { try await localExtensions.install(preview) }
            catch { localOperationError = error.localizedDescription }
        }
    }

    private func uninstall(_ item: InstalledLocalExtension) async {
        do { try await localExtensions.uninstall(item.id) }
        catch { localOperationError = error.localizedDescription }
    }

    @ViewBuilder
    private var homeSection: some View {
        if runtime.registry.metadata(for: BuiltInExtensionIDs.home) != nil {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "house.fill")
                        .font(.title3)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Home")
                            .font(.headline)
                        Text("Music controls, calendar, and camera preview.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text("Required")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Host")
            }
        }
    }

    @ViewBuilder
    private func destination(
        for route: ExtensionSettingsRoute,
        in entry: SettingsCatalogEntry?
    ) -> some View {
        if let destination = catalog.destination(for: route.destinationID) {
            destination.makeView()
                .environment(\.openShortcuts, OpenShortcutsAction(handler: onOpenShortcuts))
        } else {
            UnavailableFeatureView(featureName: entry?.displayName)
        }
    }

    private func open(_ destination: ExtensionSettingsDestination, in entry: SettingsCatalogEntry) {
        path.append(
            ExtensionSettingsRoute(featureID: entry.id, destinationID: destination.id)
        )
    }

    private func metadata(for entry: SettingsCatalogEntry) -> ExtensionMetadata? {
        guard let owner = entry.owner else { return nil }
        return runtime.registry.metadata(for: owner)
    }

    private func phase(for entry: SettingsCatalogEntry) -> ExtensionRuntimePhase {
        guard let owner = entry.owner else { return .inactive }
        return runtime.host.phase(for: owner)
    }

    private func isEnabledBinding(for entry: SettingsCatalogEntry) -> Binding<Bool> {
        Binding(
            get: {
                guard let owner = entry.owner else { return true }
                return runtime.manager.isEnabled(owner)
            },
            set: { newValue in
                guard let owner = entry.owner else { return }
                runtime.host.setEnabled(newValue, for: owner)
                presentation.refreshAll()
            }
        )
    }

    private func retry(_ entry: SettingsCatalogEntry) {
        guard let owner = entry.owner else { return }
        runtime.host.retry(owner)
        presentation.refreshAll()
    }

    /// Explicit, user-initiated permission request for a blocked feature,
    /// issued from the app process that owns the event tap. Toggling a feature
    /// never prompts on its own, and a request is never treated as a grant.
    private func grantPermission(_ entry: SettingsCatalogEntry) {
        guard let owner = entry.owner else { return }
        runtime.requestHUDInputAccess()
        runtime.host.retry(owner)
        presentation.refreshAll()
    }
}

private enum LocalExtensionSelectionError: LocalizedError {
    case updateIdentityMismatch

    var errorDescription: String? {
        "The selected package is for a different extension. Choose an update with the same extension ID."
    }
}

/// A reusable feature row.
///
/// The navigation region is a plain `Button` that fills the row except for the
/// trailing toggle, status actions, and optional disclosure indicator. The
/// toggle is a sibling, never nested inside the button, so the two actions can
/// never fire together.
private struct FeatureSettingsRow: View {
    let entry: SettingsCatalogEntry
    let summary: String?
    let phase: ExtensionRuntimePhase
    @Binding var isEnabled: Bool
    let onOpen: (ExtensionSettingsDestination) -> Void
    let onRetry: () -> Void
    let onGrantPermission: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                navigationRegion
                trailingControl
            }
            statusActions
        }
        .padding(.vertical, 4)
    }

    /// Fills the row except for the trailing controls. Opens the first (and, for
    /// first-party features, only) configuration destination.
    @ViewBuilder
    private var navigationRegion: some View {
        if let destination = entry.destinations.first {
            Button {
                onOpen(destination)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: entry.iconSystemName)
                        .font(.title3)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.displayName)
                            .font(.headline)
                        if let summary {
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Open \(entry.displayName) settings")
            .accessibilityHint(summary ?? "")
            .accessibilityAddTraits(.isButton)
        } else {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: entry.iconSystemName)
                    .font(.title3)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.displayName)
                        .font(.headline)
                    if let summary {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
        if entry.management == .runtimeManaged, entry.owner != nil {
            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                // Guard against overlapping transitions; settings access stays
                // available regardless.
                .disabled(isTransitioning)
                .accessibilityLabel("Enable \(entry.displayName)")
        }
    }

    @ViewBuilder
    private var statusActions: some View {
        switch phase {
        case .activating:
            statusLabel("Starting…")
        case .deactivating:
            statusLabel("Stopping…")
        case .failed(let message):
            HStack(spacing: 8) {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.red)
                Button("Retry", action: onRetry)
                    .buttonStyle(.link)
                    .font(.caption)
                    .accessibilityLabel("Retry \(entry.displayName) activation")
            }
        case .requiresPermission(let message):
            HStack(spacing: 8) {
                Text("\(message).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("Grant Access", action: onGrantPermission)
                    .buttonStyle(.link)
                    .font(.caption)
                    .accessibilityLabel("Grant access for \(entry.displayName)")
            }
        case .inactive, .active:
            EmptyView()
        }
    }

    private func statusLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private var isTransitioning: Bool {
        switch phase {
        case .activating, .deactivating:
            return true
        default:
            return false
        }
    }
}

/// Stale-route fallback: a definition was removed or this build excludes the
/// feature (for example Battery in `NotchKitCoreOnly`).
private struct UnavailableFeatureView: View {
    @Environment(\.dismiss) private var dismiss
    let featureName: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "questionmark.circle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("This feature is not available in this build.")
                .font(.headline)
            if let featureName {
                Text(featureName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button("Back") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .navigationTitle(featureName ?? "Unavailable")
    }
}

@available(macOS 26.0, *)
private struct LocalExtensionRow: View {
    let item: InstalledLocalExtension
    let onSetEnabled: (Bool) -> Void
    let onDetails: () -> Void
    let onRetry: () -> Void
    let onManage: () -> Void
    let onUpdate: () -> Void
    let onUninstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 12) {
                Image(systemName: item.manifest?.metadata.iconSystemName ?? "puzzlepiece.extension")
                    .font(.title3)
                    .frame(width: 24)
                Button(action: onDetails) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.displayName).font(.headline)
                        Text("Version \(item.record.extensionVersion.description) • Team \(item.record.signature.teamIdentifier)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Toggle("Desired enabled", isOn: Binding(
                    get: { item.record.desiredEnabled },
                    set: onSetEnabled
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            HStack(spacing: 8) {
                Label(item.isDiscovered ? "Approved and available" : "Not available to NotchKit", systemImage: item.isDiscovered ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(item.isDiscovered ? .green : .secondary)
                if let validationError = item.validationError {
                    Text(validationError).foregroundStyle(.red)
                }
                Spacer()
                if !item.isDiscovered {
                    Button("Retry", action: onRetry).buttonStyle(.link)
                    Button("Manage", action: onManage).buttonStyle(.link)
                }
                Menu {
                    Button("Details", action: onDetails)
                    Button("Update or Reinstall...", action: onUpdate)
                    Divider()
                    Button("Uninstall", role: .destructive, action: onUninstall)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

private struct LocalExtensionInstallConfirmation: View {
    let preview: LocalExtensionPackagePreview
    let onCancel: () -> Void
    let onInstall: () -> Void

    private var metadata: ExtensionMetadata { preview.manifest.metadata }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: metadata.iconSystemName).font(.largeTitle)
                VStack(alignment: .leading) {
                    Text(preview.isUpdate ? "Update \(metadata.displayName)?" : "Install \(metadata.displayName)?")
                        .font(.title2.bold())
                    Text("Version \(metadata.extensionVersion.description) • Signed by team \(preview.signerTeamIdentifier)")
                        .foregroundStyle(.secondary)
                }
            }
            Label(
                "This is a development/local extension. Install only packages you trust.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.orange)

            disclosureGroup

            Text("Installing does not grant any permission or system access. macOS and NotchKit will request access separately when needed.")
                .font(.callout.bold())

            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button(preview.isUpdate ? "Update" : "Install", action: onInstall)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 590)
    }

    private var disclosureGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Permissions").font(.headline)
            if preview.manifest.permissions.isEmpty {
                Text("None declared").foregroundStyle(.secondary)
            } else {
                ForEach(sortedPermissions, id: \.kind.rawValue) { permission in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(permission.kind.rawValue.replacingOccurrences(of: "-", with: " ").capitalized)
                            .fontWeight(.medium)
                        Text("\(permission.required ? "Required" : "Optional") • Owner: \(permission.owner.rawValue) • Usage key: \(permission.usageDescriptionKey)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Text("Host actions").font(.headline).padding(.top, 4)
            Text(preview.manifest.hostActions.isEmpty
                 ? "None declared"
                 : preview.manifest.hostActions.map(\.rawValue).sorted().joined(separator: ", "))
                .foregroundStyle(.secondary)
        }
    }

    private var sortedPermissions: [ExtensionDeclaredPermission] {
        preview.manifest.permissions.sorted { $0.kind.rawValue < $1.kind.rawValue }
    }
}

private struct LocalExtensionDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    let item: InstalledLocalExtension
    let onUpdate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.displayName).font(.title2.bold())
            LabeledContent("Extension ID", value: item.id.rawValue)
            LabeledContent("Version", value: item.record.extensionVersion.description)
            LabeledContent("Provider", value: item.record.providerBundleIdentifier)
            LabeledContent("Signer team", value: item.record.signature.teamIdentifier)
            LabeledContent("Desired state", value: item.record.desiredEnabled ? "Enabled" : "Disabled")
            LabeledContent("System availability", value: item.isDiscovered ? "Approved and available" : "Unavailable or awaiting approval")
            if let summary = item.manifest?.metadata.summary {
                Text(summary).foregroundStyle(.secondary)
            }
            Spacer()
            HStack {
                Button("Update or Reinstall...", action: onUpdate)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 540, height: 330)
    }
}
