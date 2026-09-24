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
    @ObservedObject private var marketplace = NotchKitRuntime.shared.marketplace

    /// Forwards a feature's "Keyboard Shortcuts" link to the root settings view.
    let onOpenShortcuts: (ShortcutsOwner) -> Void
    /// Selects the root Marketplace section. `nil` opens discovery; an identity
    /// opens that extension for an update or reinstall.
    let onOpenMarketplace: (ExtensionIdentity?) -> Void

    @State private var path: [ExtensionsRoute] = []
    @State private var searchText = ""
    @State private var packagePreview: LocalExtensionPackagePreview?
    @State private var pendingUninstall: InstalledLocalExtension?
    @State private var showsSystemExtensions = false
    @State private var localOperationError: String?

    private var runtime: NotchKitRuntime { .shared }

    private var extensionErrorMessage: String? {
        localOperationError ?? localExtensions.errorMessage
    }

    init(
        onOpenShortcuts: @escaping (ShortcutsOwner) -> Void,
        onOpenMarketplace: @escaping (ExtensionIdentity?) -> Void
    ) {
        self.onOpenShortcuts = onOpenShortcuts
        self.onOpenMarketplace = onOpenMarketplace
    }

    private var marketplaceEnvironment: MarketplaceHostEnvironment {
        let raw = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let hostVersion = raw.flatMap(ExtensionVersion.init)
            ?? ExtensionVersion(major: 1, minor: 0, patch: 0)
        return .current(hostVersion: hostVersion)
    }

    private var filteredLocalExtensions: [InstalledLocalExtension] {
        return localExtensions.installed.filter {
            ExtensionsSearch.matches(
                query: searchText,
                fields: [$0.displayName, $0.id.rawValue, $0.record.signature.teamIdentifier]
            )
        }
    }

    private var marketplaceExtensions: [InstalledLocalExtension] {
        filteredLocalExtensions.filter { $0.record.origin == .marketplace }
    }

    private var localDeveloperExtensions: [InstalledLocalExtension] {
        filteredLocalExtensions.filter { $0.record.origin == .localDeveloper }
    }

    private var filteredBuiltInEntries: [SettingsCatalogEntry] {
        return catalog.entries.filter {
            ExtensionsSearch.matches(
                query: searchText,
                fields: [$0.displayName, metadata(for: $0)?.summary]
            )
        }
    }

    private var enabledBuiltInCount: Int {
        catalog.entries.filter { entry in
            guard entry.management == .runtimeManaged, let owner = entry.owner else { return false }
            return runtime.manager.isEnabled(owner)
        }.count
    }

    private var toggleableBuiltInCount: Int {
        catalog.entries.filter { $0.management == .runtimeManaged && $0.owner != nil }.count
    }

    private var homeMatchesSearch: Bool {
        ExtensionsSearch.matches(
            query: searchText,
            fields: ["Home", "Music controls, calendar, camera preview, and more."]
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            extensionsRoot
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
            .navigationDestination(for: ExtensionsRoute.self) { route in
                destination(for: route)
            }
            .sheet(item: $packagePreview) { preview in
                LocalExtensionInstallConfirmation(
                    preview: preview,
                    onCancel: { packagePreview = nil },
                    onInstall: { install(preview) }
                )
            }
            .sheet(isPresented: $showsSystemExtensions) {
                if #available(macOS 26.0, *) {
                    SystemExtensionBrowserView()
                        .frame(minWidth: 620, minHeight: 480)
                }
            }
            .alert("Uninstall Extension?", isPresented: Binding(
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
                Text("This removes \(pendingUninstall?.displayName ?? "the extension") and all of its local contributions.")
            }
        }
        .onChange(of: catalog.revision) { _, _ in
            let builtInPath = path.compactMap { route -> ExtensionSettingsRoute? in
                guard case let .builtIn(settingsRoute) = route else { return nil }
                return settingsRoute
            }
            let validBuiltIn = Set(catalog.prune(builtInPath))
            let pruned = path.filter { route in
                guard case let .builtIn(settingsRoute) = route else { return true }
                return validBuiltIn.contains(settingsRoute)
            }
            if pruned != path { path = pruned }
        }
    }

    private var extensionsRoot: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear
                    .frame(height: 0)
                    .id("extensions.top")

                VStack(alignment: .leading, spacing: 22) {
                    extensionsHeader
                    if let extensionErrorMessage {
                        errorBanner(extensionErrorMessage)
                    }
                    homeSection
                    builtInSection
                    localExtensionsSection
                }
                .padding(.horizontal, 30)
                .padding(.top, 22)
                .padding(.bottom, 26)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .onAppear {
                proxy.scrollTo("extensions.top", anchor: .top)
            }
        }
        .navigationTitle("")
        .accessibilityIdentifier("extensions.root")
    }

    private func errorBanner(_ message: String) -> some View {
        ExtensionCard {
            HStack(alignment: .top, spacing: 14) {
                ExtensionIcon(systemName: "exclamationmark.triangle.fill", tint: .red)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Extension action failed")
                        .font(.headline)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 12)
                Button("Retry") {
                    clearExtensionError()
                    Task { await localExtensions.refresh() }
                }
                Button("Dismiss") { clearExtensionError() }
            }
            .padding(16)
        }
        .accessibilityIdentifier("extensions.error")
    }

    private func clearExtensionError() {
        localOperationError = nil
        localExtensions.clearError()
    }

    private var extensionsHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                titleBlock
                Spacer(minLength: 20)
                searchField
                discoverButton
                managementMenu
            }

            VStack(alignment: .leading, spacing: 14) {
                titleBlock
                HStack(spacing: 10) {
                    searchField
                    discoverButton
                    managementMenu
                }
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Extensions")
                .font(.largeTitle.bold())
            Text("Shape NotchKit with built-in and installed modules.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search extensions", text: $searchText)
                .textFieldStyle(.plain)
                .accessibilityIdentifier("extensions.search")
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear extension search")
                .accessibilityIdentifier("extensions.search.clear")
            }
        }
        .padding(.horizontal, 12)
        .frame(minWidth: 180, idealWidth: 260, maxWidth: 300, minHeight: 38)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
        }
    }

    private var discoverButton: some View {
        Button {
            onOpenMarketplace(nil)
        } label: {
            Label("Discover", systemImage: "sparkles")
                .fontWeight(.medium)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityIdentifier("extensions.discover")
    }

    private var managementMenu: some View {
        Menu {
            Button("Discover Extensions", systemImage: "sparkles") {
                onOpenMarketplace(nil)
            }
            Divider()
            if #available(macOS 26.0, *) {
                Button("Install Local Extension...", systemImage: "shippingbox") { choosePackage() }
                Button("Manage System Extensions...", systemImage: "gearshape.2") {
                    showsSystemExtensions = true
                }
                Divider()
                Button("Refresh Extensions", systemImage: "arrow.clockwise") {
                    Task { await localExtensions.refresh() }
                }
                .disabled(localExtensions.isRefreshing)
            } else {
                Button("Native extensions require macOS 26", systemImage: "exclamationmark.triangle") {}
                    .disabled(true)
            }
        } label: {
            Text("Manage")
                .fontWeight(.medium)
                .frame(minWidth: 76)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 1)
        }
        .accessibilityIdentifier("extensions.manage")
    }

    @ViewBuilder
    private var builtInSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Built-in")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.leading, 10)

            ExtensionCard {
                if catalog.entries.isEmpty {
                    settingsMessage("No built-in features are available.")
                } else if filteredBuiltInEntries.isEmpty {
                    settingsMessage("No built-in features match your search.")
                } else {
                    ForEach(Array(filteredBuiltInEntries.enumerated()), id: \.element.id) { index, entry in
                        FeatureSettingsRow(
                            entry: entry,
                            summary: metadata(for: entry)?.summary,
                            phase: phase(for: entry),
                            isEnabled: isEnabledBinding(for: entry),
                            onOpen: { destination in open(destination, in: entry) },
                            onRetry: { retry(entry) },
                            onGrantPermission: { grantPermission(entry) }
                        )
                        if index < filteredBuiltInEntries.count - 1 { Divider() }
                    }
                }
            }

            if searchText.isEmpty, toggleableBuiltInCount > 0 {
                Text("\(enabledBuiltInCount) of \(toggleableBuiltInCount) enabled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.top, 2)
                    .accessibilityIdentifier("extensions.enabled-count")
            }
        }
        .accessibilityIdentifier("extensions.built-in")
    }

    private func settingsMessage(_ message: String) -> some View {
        Text(message)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
    }

    @ViewBuilder
    private var localExtensionsSection: some View {
        if #available(macOS 26.0, *) {
            if localExtensions.installed.isEmpty {
                settingsCardSection(title: "Installed extensions") {
                    ExtensionStateView(
                        systemImage: "puzzlepiece.extension",
                        title: "No extensions installed",
                        message: "Discover extensions from NotchKit Hub, or install a local development package."
                    ) {
                        Button("Discover") { onOpenMarketplace(nil) }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("extensions.discover-empty")
                    }
                    .accessibilityIdentifier("extensions.installed.empty")
                }
            } else if filteredLocalExtensions.isEmpty {
                settingsCardSection(title: "Installed extensions") {
                    ExtensionStateView(
                        systemImage: "magnifyingglass",
                        title: "No installed matches",
                        message: "Try another name, extension ID, or signing team."
                    ) {
                        Button("Clear Search") { searchText = "" }
                    }
                    .accessibilityIdentifier("extensions.installed.no-results")
                }
            } else {
                if !marketplaceExtensions.isEmpty {
                    settingsCardSection(title: "Marketplace extensions") {
                        ForEach(Array(marketplaceExtensions.enumerated()), id: \.element.id) { index, item in
                            extensionRow(for: item)
                            if index < marketplaceExtensions.count - 1 { Divider() }
                        }
                    }
                }
                if !localDeveloperExtensions.isEmpty {
                    settingsCardSection(title: "Local developer extensions") {
                        ForEach(Array(localDeveloperExtensions.enumerated()), id: \.element.id) { index, item in
                            extensionRow(for: item)
                            if index < localDeveloperExtensions.count - 1 { Divider() }
                        }
                    }
                }
            }
        } else {
            settingsCardSection(title: "Installed extensions") {
                ExtensionStateView(
                    systemImage: "macbook",
                    title: "A newer macOS is required",
                    message: "Native ExtensionKit extensions require macOS 26 or later."
                )
                .accessibilityIdentifier("extensions.installed.unsupported")
            }
        }
    }

    private func settingsCardSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
            ExtensionCard(content: content)
        }
        .accessibilityIdentifier("extensions.section.\(title.lowercased().replacingOccurrences(of: " ", with: "-"))")
    }

    @available(macOS 26.0, *)
    private func extensionRow(for item: InstalledLocalExtension) -> some View {
        LocalExtensionRow(
            item: item,
            onSetEnabled: { localExtensions.setDesiredEnabled($0, for: item.id) },
            onDetails: { path.append(.installed(item.id)) },
            onRetry: { Task { await localExtensions.refresh() } },
            onManage: { showsSystemExtensions = true },
            onUpdate: {
                if item.record.origin == .marketplace {
                    onOpenMarketplace(item.id)
                } else {
                    choosePackage(updating: item.id)
                }
            },
            onRollback: item.record.previousRelease == nil ? nil : {
                Task { await rollback(item) }
            },
            onUninstall: { pendingUninstall = item }
        )
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

    private func rollback(_ item: InstalledLocalExtension) async {
        do {
            if item.record.previousRelease?.origin == .marketplace {
                guard #available(macOS 26.0, *) else { return }
                try await marketplace.rollback(
                    item,
                    environment: marketplaceEnvironment,
                    localExtensions: localExtensions
                )
            } else {
                try await localExtensions.rollback(item.id)
            }
        }
        catch { localOperationError = error.localizedDescription }
    }

    @ViewBuilder
    private var homeSection: some View {
        if runtime.registry.metadata(for: BuiltInExtensionIDs.home) != nil, homeMatchesSearch {
            VStack(alignment: .leading, spacing: 8) {
                Text("Core")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 10)
                ExtensionCard {
                    HStack(alignment: .center, spacing: 14) {
                        ExtensionIcon(systemName: "house.fill", tint: .effectiveAccent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Home")
                                .font(.headline)
                            Text("Music controls, calendar, camera preview, and more.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Text("Required")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(.quaternary, in: Capsule())
                    }
                    .padding(16)
                }
            }
            .accessibilityIdentifier("extensions.core.home")
        }
    }

    @ViewBuilder
    private func destination(for route: ExtensionsRoute) -> some View {
        switch route {
        case let .builtIn(settingsRoute):
            if let destination = catalog.destination(for: settingsRoute.destinationID) {
                destination.makeView()
                    .environment(\.openShortcuts, OpenShortcutsAction(handler: onOpenShortcuts))
            } else {
                UnavailableFeatureView(
                    featureName: catalog.entries.first { $0.id == settingsRoute.featureID }?.displayName
                )
            }
        case let .installed(id):
            if let item = localExtensions.installed.first(where: { $0.id == id }) {
                LocalExtensionDetailsView(item: item) {
                    if item.record.origin == .marketplace {
                        onOpenMarketplace(item.id)
                    } else {
                        choosePackage(updating: item.id)
                    }
                }
            } else {
                UnavailableFeatureView(featureName: nil)
            }
        }
    }

    private func open(_ destination: ExtensionSettingsDestination, in entry: SettingsCatalogEntry) {
        path.append(
            .builtIn(ExtensionSettingsRoute(featureID: entry.id, destinationID: destination.id))
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

private struct ExtensionCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.035), radius: 8, y: 3)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
        }
    }
}

private struct ExtensionIcon: View {
    let systemName: String
    var tint: Color = .secondary

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 38, height: 38)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
    }
}

private struct ExtensionStateView<Actions: View>: View {
    let systemImage: String
    let title: String
    let message: String
    let actions: Actions

    init(
        systemImage: String,
        title: String,
        message: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        HStack(spacing: 14) {
            ExtensionIcon(systemName: systemImage)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            actions
        }
        .padding(16)
    }
}

private extension ExtensionStateView where Actions == EmptyView {
    init(systemImage: String, title: String, message: String) {
        self.init(systemImage: systemImage, title: title, message: message) { EmptyView() }
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
                .padding(.leading, 50)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
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
                    ExtensionIcon(systemName: entry.iconSystemName, tint: .effectiveAccent)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.displayName)
                            .font(.headline)
                        if let summary {
                            Text(summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 5)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Open \(entry.displayName) settings")
            .accessibilityHint(summary ?? "")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("extensions.feature.\(entry.id.rawValue).open")
        } else {
            HStack(alignment: .top, spacing: 12) {
                ExtensionIcon(systemName: entry.iconSystemName)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.displayName)
                        .font(.headline)
                    if let summary {
                        Text(summary)
                            .font(.subheadline)
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
                .controlSize(.regular)
                // Guard against overlapping transitions; settings access stays
                // available regardless.
                .disabled(isTransitioning)
                .accessibilityLabel("Enable \(entry.displayName)")
                .accessibilityIdentifier("extensions.feature.\(entry.id.rawValue).enabled")
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
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.red)
                Button("Retry", action: onRetry)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .font(.caption)
                    .accessibilityLabel("Retry \(entry.displayName) activation")
            }
        case .requiresPermission(let message):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                Text("\(message).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("Grant Access", action: onGrantPermission)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
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
        .accessibilityIdentifier("extensions.detail.unavailable")
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
    let onRollback: (() -> Void)?
    let onUninstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 14) {
                Button(action: onDetails) {
                    HStack(spacing: 14) {
                        ExtensionIcon(
                            systemName: item.manifest?.metadata.iconSystemName ?? "puzzlepiece.extension",
                            tint: item.record.marketplaceRevocationStatus == .revoked ? .red : .effectiveAccent
                        )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.displayName).font(.headline)
                            Text("Version \(item.record.extensionVersion.description) • Team \(item.record.signature.teamIdentifier)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(item.displayName) details")
                .accessibilityIdentifier("extensions.installed.\(item.id.rawValue).open")
                Toggle("Desired enabled", isOn: Binding(
                    get: { item.record.desiredEnabled },
                    set: onSetEnabled
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.regular)
                .disabled(item.record.marketplaceRevocationStatus == .revoked)
                .accessibilityLabel("Enable \(item.displayName)")
                .accessibilityIdentifier("extensions.installed.\(item.id.rawValue).enabled")
            }
            HStack(spacing: 8) {
                if item.record.marketplaceRevocationStatus == .revoked {
                    Label("Revoked by NotchKit Hub", systemImage: "exclamationmark.shield.fill")
                        .foregroundStyle(.red)
                }
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
                    if let onRollback {
                        Button("Roll Back to Previous Version", action: onRollback)
                    }
                    Divider()
                    Button("Uninstall", role: .destructive, action: onUninstall)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("More actions for \(item.displayName)")
                .accessibilityIdentifier("extensions.installed.\(item.id.rawValue).menu")
            }
            .font(.caption)
            .padding(.leading, 52)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityIdentifier("extensions.installed.\(item.id.rawValue)")
    }
}

private struct LocalExtensionInstallConfirmation: View {
    let preview: LocalExtensionPackagePreview
    let onCancel: () -> Void
    let onInstall: () -> Void

    private var metadata: ExtensionMetadata { preview.manifest.metadata }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 14) {
                        ExtensionIcon(systemName: metadata.iconSystemName, tint: .effectiveAccent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(preview.isUpdate ? "Update \(metadata.displayName)?" : "Install \(metadata.displayName)?")
                                .font(.title2.bold())
                            Text("Version \(metadata.extensionVersion.description) • Team \(preview.signerTeamIdentifier)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Label(
                        "This is a local development extension. Install only packages you trust.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.orange)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

                    disclosureGroup

                    Text("Installing does not grant permission or system access. macOS and NotchKit request access separately when needed.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("extensions.install.cancel")
                Button(preview.isUpdate ? "Update" : "Install", action: onInstall)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("extensions.install.confirm")
            }
            .padding(16)
        }
        .frame(minWidth: 480, idealWidth: 590, maxWidth: 680, minHeight: 360, idealHeight: 480, maxHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("extensions.install.sheet")
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
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    ExtensionIcon(
                        systemName: item.manifest?.metadata.iconSystemName ?? "puzzlepiece.extension",
                        tint: .effectiveAccent
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.displayName).font(.title2.bold())
                        if let summary = item.manifest?.metadata.summary {
                            Text(summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                ExtensionCard {
                    VStack(spacing: 0) {
                        detailRow("Extension ID", item.id.rawValue)
                        Divider()
                        detailRow("Version", item.record.extensionVersion.description)
                        Divider()
                        detailRow("Provider", item.record.providerBundleIdentifier)
                        Divider()
                        detailRow("Signer team", item.record.signature.teamIdentifier)
                        Divider()
                        detailRow("Desired state", item.record.desiredEnabled ? "Enabled" : "Disabled")
                        Divider()
                        detailRow(
                            "System availability",
                            item.isDiscovered ? "Approved and available" : "Unavailable or awaiting approval"
                        )
                    }
                    .padding(.horizontal, 16)
                }

                HStack {
                    Button("Update or Reinstall...", action: onUpdate)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("extensions.details.update")
                    Spacer()
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("extensions.details.done")
                }
            }
            .padding(30)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Extension Details")
        .accessibilityIdentifier("extensions.details.\(item.id.rawValue)")
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        LabeledContent(label, value: value)
            .textSelection(.enabled)
            .padding(.vertical, 11)
    }
}
