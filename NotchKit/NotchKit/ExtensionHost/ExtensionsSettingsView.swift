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

import NotchExtensionSDK
import NotchExtensionRuntime
import SwiftUI

/// The Extensions settings hub.
struct ExtensionsSettingsView: View {
    @ObservedObject private var catalog = NotchKitRuntime.shared.settingsCatalog
    @ObservedObject private var presentation = NotchKitRuntime.shared.presentation

    /// Forwards a feature's "Keyboard Shortcuts" link to the root settings view.
    let onOpenShortcuts: (ShortcutsOwner) -> Void

    @State private var path: [ExtensionSettingsRoute] = []

    private var runtime: NotchKitRuntime { .shared }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                homeSection

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
        }
        .onChange(of: catalog.revision) { _, _ in
            let pruned = catalog.prune(path)
            if pruned != path { path = pruned }
        }
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
