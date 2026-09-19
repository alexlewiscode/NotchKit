import ExtensionFoundation
import SwiftUI

struct HostContentView: View {
    @State private var discovery = NativeExtensionDiscovery()
    @State private var selectedIdentity: AppExtensionIdentity?
    @State private var session = RemoteExtensionSession()
    @State private var showsExtensionBrowser = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await discovery.start()
            reconcileSelection()
        }
        .onChange(of: discovery.identities) { _, _ in
            reconcileSelection()
        }
        .sheet(isPresented: $showsExtensionBrowser) {
            ExtensionBrowserView()
                .frame(minWidth: 640, minHeight: 420)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("NOTCHKIT LABS")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.5)
                Text("Native extensions")
                    .font(.title2.weight(.semibold))
            }

            if discovery.identities.isEmpty {
                ContentUnavailableView(
                    "No Enabled Extensions",
                    systemImage: "puzzlepiece.extension",
                    description: Text("Install the Pomodoro provider, then enable it in the system extension browser.")
                )
            } else {
                ForEach(discovery.identities, id: \.id) { identity in
                    Button {
                        guard selectedIdentity != identity else { return }
                        session.deactivate()
                        selectedIdentity = identity
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "timer")
                                .frame(width: 24, height: 24)
                                .background(.red.opacity(0.18), in: RoundedRectangle(cornerRadius: 7))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(identity.localizedName)
                                    .fontWeight(.medium)
                                Text(identity.bundleIdentifier)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(9)
                        .background(
                            selectedIdentity == identity ? Color.accentColor.opacity(0.16) : .clear,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            if discovery.unapprovedCount > 0 || discovery.disabledCount > 0 {
                Text("\(discovery.unapprovedCount) awaiting approval, \(discovery.disabledCount) disabled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Manage System Extensions", systemImage: "switch.2") {
                showsExtensionBrowser = true
            }
            .buttonStyle(.borderedProminent)

            Button("Refresh", systemImage: "arrow.clockwise") {
                Task {
                    await discovery.start()
                    reconcileSelection()
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
        .frame(width: 280)
    }

    @ViewBuilder
    private var detail: some View {
        VStack(spacing: 0) {
            HStack {
                statusBadge
                Spacer()
                if session.phase == .active {
                    Button("Crash Extension", systemImage: "bolt.trianglebadge.exclamationmark") {
                        session.crashForTesting()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(16)

            Divider()

            if let identity = selectedIdentity {
                RemoteExtensionView(
                    identity: identity,
                    extensionID: "com.notchkit.prototype.pomodoro",
                    sceneID: "main",
                    session: session
                )
                    .id(identity.id)
            } else if let error = discovery.errorMessage {
                ContentUnavailableView(
                    "Discovery Failed",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                ContentUnavailableView(
                    "Select an Extension",
                    systemImage: "rectangle.on.rectangle.slash",
                    description: Text("Enabled native extension scenes appear here.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusBadge: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(session.phase.rawValue.capitalized)
                .font(.caption.weight(.semibold))
            if let message = session.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary, in: Capsule())
    }

    private var statusColor: Color {
        switch session.phase {
        case .active: .green
        case .activating: .orange
        case .failed, .interrupted: .red
        case .discovered, .disabled, .inactive: .secondary
        }
    }

    private func reconcileSelection() {
        if let selectedIdentity, discovery.identities.contains(selectedIdentity) {
            return
        }
        session.deactivate()
        selectedIdentity = discovery.identities.first
    }
}
