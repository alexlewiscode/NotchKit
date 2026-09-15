//
//  ExtensionsSettingsView.swift
//  NotchKit
//
//  The Extensions settings hub.
//
//  Lists first-party definitions and host-owned legacy feature adapters from the
//  authoritative `SettingsCatalog`. It reads no contribution store settings and
//  constructs no extension instance. Only runtime-managed features (Battery in
//  this milestone) expose an enable/disable toggle; Home is required and every
//  other feature is configuration-only.
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
                            CatalogEntryRow(
                                entry: entry,
                                metadata: metadata(for: entry),
                                phase: phase(for: entry),
                                isEnabled: isEnabledBinding(for: entry),
                                onConfigure: { destination in open(destination, in: entry) },
                                onRetry: { retry(entry) }
                            )
                        }
                    }
                } header: {
                    Text("Built-in feature settings")
                } footer: {
                    Text(
                        "Extensions are compiled into NotchKit. Only Battery can be enabled or disabled; "
                            + "the other features remain available and are configured here."
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
        guard entry.owner != nil else { return }
        // `reconcileNow()` re-runs activation for an enabled, failed extension.
        // It does not call `setEnabled(true)`, which would be a no-op.
        runtime.host.reconcileNow()
        presentation.refreshAll()
    }
}

private struct CatalogEntryRow: View {
    let entry: SettingsCatalogEntry
    let metadata: ExtensionMetadata?
    let phase: ExtensionRuntimePhase
    @Binding var isEnabled: Bool
    let onConfigure: (ExtensionSettingsDestination) -> Void
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.iconSystemName)
                .font(.title3)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.displayName)
                        .font(.headline)
                    statusBadge
                }
                if let summary = metadata?.summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if case .failed(let message) = phase {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.red)
                    Button("Retry") { onRetry() }
                        .buttonStyle(.link)
                        .font(.caption)
                        .accessibilityLabel("Retry \(entry.displayName) activation")
                }

                if !entry.destinations.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(entry.destinations) { destination in
                            Button(destination.title) {
                                onConfigure(destination)
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }
                    }
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)

            trailingControl
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch phase {
        case .failed:
            Text("Failed")
                .font(.caption2)
                .foregroundStyle(.red)
        case .activating:
            Text("Starting")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .deactivating:
            Text("Stopping")
                .font(.caption2)
                .foregroundStyle(.secondary)
        default:
            if entry.management == .configurationOnly {
                Text("Configuration only")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if !isEnabled {
                Text("Disabled")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
        if entry.management == .runtimeManaged {
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
