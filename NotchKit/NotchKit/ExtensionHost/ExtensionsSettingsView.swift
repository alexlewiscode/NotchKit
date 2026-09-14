//
//  ExtensionsSettingsView.swift
//  NotchKit
//
//  Minimal Extensions hub listing first-party extensions and their state.
//

import NotchExtensionSDK
import NotchExtensionRuntime
import SwiftUI

/// The Extensions settings hub.
///
/// Lists first-party definitions, exposes enabled state and lifecycle phase,
/// and routes to a declared settings destination while the extension is active.
/// There is no marketplace, search, install, or delete surface.
struct ExtensionsSettingsView: View {
    @ObservedObject private var presentation = NotchKitRuntime.shared.presentation

    @State private var revision = UUID()
    @State private var presentedSettings: ExtensionSettingsDestination?

    private var runtime: NotchKitRuntime { .shared }

    var body: some View {
        Form {
            Section {
                ForEach(runtime.registry.metadata) { metadata in
                    ExtensionRow(
                        metadata: metadata,
                        phase: runtime.host.phase(for: metadata.id),
                        isEnabled: isEnabledBinding(for: metadata),
                        settingsDestinations: settingsDestinations(for: metadata.id)
                    ) { destination in
                        presentedSettings = destination
                    }
                }
            } header: {
                Text("First-party extensions")
            } footer: {
                Text(
                    "Extensions are compiled into NotchKit. Disabling one stops its services "
                        + "and hides its content, entry points, and settings."
                )
            }
        }
        .navigationTitle("Extensions")
        .accentColor(.effectiveAccent)
        .id(revision)
        .sheet(item: $presentedSettings) { destination in
            VStack(spacing: 0) {
                destination.makeView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                HStack {
                    Spacer()
                    Button("Done") { presentedSettings = nil }
                        .keyboardShortcut(.defaultAction)
                }
                .padding()
            }
            .frame(minWidth: 520, minHeight: 420)
        }
    }

    private func settingsDestinations(for id: ExtensionIdentity) -> [ExtensionSettingsDestination] {
        runtime.contributions.settingsDestinations.filter {
            runtime.contributions.extensionID(forSettingsDestination: $0.id) == id
        }
    }

    private func isEnabledBinding(for metadata: ExtensionMetadata) -> Binding<Bool> {
        Binding(
            get: { runtime.manager.isEnabled(metadata.id) },
            set: { newValue in
                runtime.host.setEnabled(newValue, for: metadata.id)
                presentation.refreshAll()
                revision = UUID()
            }
        )
    }
}

private struct ExtensionRow: View {
    let metadata: ExtensionMetadata
    let phase: ExtensionRuntimePhase
    @Binding var isEnabled: Bool
    let settingsDestinations: [ExtensionSettingsDestination]
    let onOpenSettings: (ExtensionSettingsDestination) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: metadata.iconSystemName)
                .font(.title3)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(metadata.displayName)
                        .font(.headline)
                    if case .failed = phase {
                        Text("Failed")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
                if let summary = metadata.summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !settingsDestinations.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(settingsDestinations) { destination in
                            Button(destination.title) {
                                onOpenSettings(destination)
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }
                    }
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)

            if metadata.id == BuiltInExtensionIDs.home {
                Text("Required")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
