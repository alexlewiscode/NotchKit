//
//  ExtensionsSettingsView.swift
//  NotchKit
//
//  Minimal Extensions hub listing first-party extensions and their state.
//

import NotchAPI
import NotchExtensions
import SwiftUI

/// The Extensions settings hub.
///
/// Deliberately minimal in Phase 1: it lists first-party descriptors, exposes
/// their enabled state, and provides a route to a declared settings
/// destination. There is no marketplace, search, install, or delete surface.
struct ExtensionsSettingsView: View {
    @ObservedObject private var router = NotchKitRuntime.shared.router

    @State private var revision = UUID()
    @State private var presentedSettings: ExtensionSettingsDestination?

    private var runtime: NotchKitRuntime { .shared }

    var body: some View {
        Form {
            Section {
                ForEach(runtime.registry.descriptors) { descriptor in
                    ExtensionRow(
                        descriptor: descriptor,
                        isEnabled: isEnabledBinding(for: descriptor),
                        settingsDestinations: descriptor.settingsDestinations
                    ) { destination in
                        presentedSettings = destination
                    }
                }
            } header: {
                Text("First-party extensions")
            } footer: {
                Text(
                    "Extensions are compiled into NotchKit. Disabling one hides its content, "
                        + "entry points, and settings."
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

    private func isEnabledBinding(for descriptor: ExtensionDescriptor) -> Binding<Bool> {
        Binding(
            get: { runtime.manager.isEnabled(descriptor.id) },
            set: { newValue in
                runtime.manager.setEnabled(newValue, for: descriptor.id)
                runtime.refresh()
                revision = UUID()
            }
        )
    }
}

private struct ExtensionRow: View {
    let descriptor: ExtensionDescriptor
    @Binding var isEnabled: Bool
    let settingsDestinations: [ExtensionSettingsDestination]
    let onOpenSettings: (ExtensionSettingsDestination) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: descriptor.iconSystemName)
                .font(.title3)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(descriptor.displayName)
                    .font(.headline)
                if let summary = descriptor.summary {
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

            if descriptor.id == BuiltInExtensionIDs.home {
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