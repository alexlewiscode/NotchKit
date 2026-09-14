//
//  SoftwareUpdater.swift
//  NotchKit
//
//  Created by Richard Kunkli on 09/08/2024.
//

import SwiftUI
import Sparkle

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        // Upstream automatic updates are disabled until a NotchKit update feed
        // and signing key exist. Do not observe the upstream updater.
        canCheckForUpdates = false
    }
}

struct CheckForUpdatesView: View {
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
    }

    var body: some View {
        Button("Check for Updates…") {}
            .disabled(true)
            .help("Updates are disabled until a NotchKit update feed and signing key are configured.")
    }
}

struct UpdaterSettingsView: View {
    private let updater: SPUUpdater

    @State private var automaticallyChecksForUpdates: Bool
    @State private var automaticallyDownloadsUpdates: Bool

    init(updater: SPUUpdater) {
        self.updater = updater
        self.automaticallyChecksForUpdates = false
        self.automaticallyDownloadsUpdates = false
    }

    var body: some View {
        Section {
            Text("Automatic updates are disabled until a NotchKit update feed and signing key are configured.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Toggle("Automatically check for updates", isOn: $automaticallyChecksForUpdates)
                .disabled(true)

            Toggle("Automatically download updates", isOn: $automaticallyDownloadsUpdates)
                .disabled(true)
        } header: {
            HStack {
                Text("Software updates")
            }
        }
    }
}
