import AppKit
import NotchExtensionSDK
import SwiftUI

/// A self-contained Marketplace settings root. It owns discovery navigation and
/// install confirmation while the caller retains the trusted installation path.
struct MarketplaceSettingsView: View {
    @ObservedObject var marketplace: MarketplaceCatalogCoordinator
    let installedVersions: [ExtensionIdentity: ExtensionVersion]
    let environment: MarketplaceHostEnvironment
    let initialSelection: ExtensionIdentity?
    let onInstall: (MarketplaceCatalogEntry) -> Void

    @State private var path: [MarketplaceSettingsRoute] = []
    @State private var searchText = ""
    @State private var selectedCategory = MarketplaceCategory.all
    @State private var confirmation: MarketplaceCatalogEntry?

    init(
        marketplace: MarketplaceCatalogCoordinator,
        installedVersions: [ExtensionIdentity: ExtensionVersion],
        environment: MarketplaceHostEnvironment,
        initialSelection: ExtensionIdentity? = nil,
        onInstall: @escaping (MarketplaceCatalogEntry) -> Void
    ) {
        self.marketplace = marketplace
        self.installedVersions = installedVersions
        self.environment = environment
        self.initialSelection = initialSelection
        self.onInstall = onInstall
    }

    var body: some View {
        NavigationStack(path: $path) {
            MarketplaceCatalogRoot(
                marketplace: marketplace,
                installedVersions: installedVersions,
                environment: environment,
                searchText: $searchText,
                selectedCategory: $selectedCategory,
                onOpenEntry: { path.append(.catalog($0)) },
                onOpenSample: { path.append(.sample($0)) },
                onInstall: { confirmation = $0 }
            )
            .navigationDestination(for: MarketplaceSettingsRoute.self) { route in
                switch route {
                case let .catalog(id):
                    if let entry = marketplace.entry(for: id) {
                        MarketplaceCatalogDetailsView(
                            entry: entry,
                            installedVersion: installedVersions[id],
                            environment: environment,
                            operation: marketplace.operations[id],
                            onInstall: { confirmation = entry }
                        )
                    } else {
                        MarketplaceUnavailableDetailView()
                    }
                case let .sample(id):
                    if let sample = MarketplaceSample.samples.first(where: { $0.id == id }) {
                        MarketplaceSampleDetailsView(sample: sample)
                    } else {
                        MarketplaceUnavailableDetailView()
                    }
                }
            }
            .sheet(item: $confirmation) { entry in
                MarketplaceInstallConfirmation(
                    entry: entry,
                    isUpdate: installedVersions[entry.id] != nil,
                    onCancel: { confirmation = nil },
                    onInstall: {
                        confirmation = nil
                        onInstall(entry)
                    }
                )
            }
        }
        .onAppear {
            if case .idle = marketplace.phase { marketplace.refresh() }
            if let initialSelection, path.isEmpty {
                path.append(.catalog(initialSelection))
            }
        }
        .accessibilityIdentifier("marketplace.settings.root")
    }
}

private enum MarketplaceSettingsRoute: Hashable {
    case catalog(ExtensionIdentity)
    case sample(String)
}

enum MarketplaceCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case productivity = "Productivity"
    case media = "Media"
    case utilities = "Utilities"
    case developer = "Developer"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return String(localized: "All")
        case .productivity: return String(localized: "Productivity")
        case .media: return String(localized: "Media")
        case .utilities: return String(localized: "Utilities")
        case .developer: return String(localized: "Developer")
        }
    }
}

private struct MarketplaceCatalogRoot: View {
    @ObservedObject var marketplace: MarketplaceCatalogCoordinator
    let installedVersions: [ExtensionIdentity: ExtensionVersion]
    let environment: MarketplaceHostEnvironment
    @Binding var searchText: String
    @Binding var selectedCategory: MarketplaceCategory
    let onOpenEntry: (ExtensionIdentity) -> Void
    let onOpenSample: (String) -> Void
    let onInstall: (MarketplaceCatalogEntry) -> Void

    private let columns = [GridItem(.adaptive(minimum: 250, maximum: 390), spacing: 16)]

    private var entries: [MarketplaceCatalogEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return (marketplace.snapshot?.entries ?? []).filter { entry in
            let matchesCategory = selectedCategory == .all || entry.marketplaceCategory == selectedCategory
            let matchesQuery = query.isEmpty
                || entry.displayName.localizedCaseInsensitiveContains(query)
                || entry.summary.localizedCaseInsensitiveContains(query)
                || entry.publisher.displayName.localizedCaseInsensitiveContains(query)
                || entry.latest.capabilities.contains(where: { $0.localizedCaseInsensitiveContains(query) })
            return matchesCategory && matchesQuery
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if #available(macOS 26.0, *) {
                    content
                } else {
                    MarketplaceMessageCard(
                        icon: "macbook",
                        title: "Marketplace requires macOS 26",
                        message: "Signed native extensions are available on macOS 26 or later."
                    )
                }
            }
            .frame(maxWidth: 1040, alignment: .leading)
            .padding(.horizontal, 30)
            .padding(.vertical, 24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Marketplace")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Extension Marketplace")
                        .font(.largeTitle.bold())
                    Text("Find trusted ways to make your notch more useful.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Button {
                    marketplace.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(marketplace.phase == .loading || marketplace.phase == .unavailable)
                .accessibilityIdentifier("marketplace.refresh")
            }

            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search extensions", text: $searchText)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("marketplace.search")
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear marketplace search")
                }
            }
            .padding(.horizontal, 13)
            .frame(height: 40)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.6))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch marketplace.phase {
        case .unavailable:
            sampleContent
        case .idle, .loading:
            if marketplace.snapshot == nil {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Loading verified extensions...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
                .accessibilityIdentifier("marketplace.loading")
            } else {
                loadedContent
            }
        case let .failed(message):
            MarketplaceMessageCard(
                icon: "wifi.exclamationmark",
                title: "Marketplace unavailable",
                message: LocalizedStringKey(message),
                actionTitle: "Try Again",
                action: marketplace.refresh
            )
        case .loaded:
            loadedContent
        }
    }

    private var loadedContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            if marketplace.isUsingCachedCatalog {
                Label("Showing the last verified catalog.", systemImage: "externaldrive")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("marketplace.cached-catalog")
            }
            if let error = marketplace.refreshError {
                Label(error, systemImage: "wifi.exclamationmark")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("marketplace.refresh-error")
            }
            if searchText.isEmpty, selectedCategory == .all,
               let featured = marketplace.snapshot?.entries.first {
                MarketplaceFeaturedCard(
                    entry: featured,
                    installedVersion: installedVersions[featured.id],
                    compatibility: MarketplaceReleaseEvaluator.compatibility(of: featured.latest, with: environment),
                    operation: marketplace.operations[featured.id],
                    onOpen: { onOpenEntry(featured.id) },
                    onInstall: { onInstall(featured) }
                )
            }
            categoryPicker
            VStack(alignment: .leading, spacing: 12) {
                Text(selectedCategory == .all ? String(localized: "Explore extensions") : selectedCategory.title)
                    .font(.title2.bold())
                if entries.isEmpty {
                    MarketplaceMessageCard(
                        icon: "magnifyingglass",
                        title: "No extensions found",
                        message: searchText.isEmpty
                            ? "No extensions are available in this category."
                            : "Try another search or category."
                    )
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        ForEach(entries) { entry in
                            MarketplaceExtensionCard(
                                entry: entry,
                                installedVersion: installedVersions[entry.id],
                                compatibility: MarketplaceReleaseEvaluator.compatibility(of: entry.latest, with: environment),
                                operation: marketplace.operations[entry.id],
                                onOpen: { onOpenEntry(entry.id) },
                                onInstall: { onInstall(entry) }
                            )
                        }
                    }
                }
            }
        }
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MarketplaceCategory.allCases) { category in
                    Button(category.title) { selectedCategory = category }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .tint(selectedCategory == category ? .accentColor : .secondary)
                        .accessibilityAddTraits(selectedCategory == category ? .isSelected : [])
                        .accessibilityIdentifier("marketplace.category.\(category.rawValue.lowercased())")
                }
            }
        }
        .accessibilityLabel("Marketplace categories")
    }

    private var sampleContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            MarketplaceMessageCard(
                icon: "eye",
                title: "Local preview only",
                message: "NotchKit Hub is not configured in this build. These sample cards demonstrate the Marketplace layout and cannot be installed."
            )
            Text("Sample extensions")
                .font(.title2.bold())
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(MarketplaceSample.samples) { sample in
                    MarketplaceSampleCard(sample: sample) { onOpenSample(sample.id) }
                }
            }
        }
        .accessibilityIdentifier("marketplace.local-preview")
    }
}

private extension MarketplaceCatalogEntry {
    var marketplaceCategory: MarketplaceCategory {
        let values = latest.capabilities
            .union(latest.hostActions.map(\.rawValue))
            .map { $0.lowercased() }
        if values.contains(where: { $0.contains("audio") || $0.contains("media") || $0.contains("camera") }) {
            return .media
        }
        if values.contains(where: { $0.contains("debug") || $0.contains("developer") || $0.contains("script") }) {
            return .developer
        }
        if values.contains(where: { $0.contains("calendar") || $0.contains("shortcut") || $0.contains("destination") }) {
            return .productivity
        }
        return .utilities
    }
}

private struct MarketplaceFeaturedCard: View {
    let entry: MarketplaceCatalogEntry
    let installedVersion: ExtensionVersion?
    let compatibility: MarketplaceCompatibilityState
    let operation: String?
    let onOpen: () -> Void
    let onInstall: () -> Void

    var body: some View {
        HStack(spacing: 22) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.accentColor.opacity(0.16))
                Image(systemName: entry.iconSystemName)
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 88, height: 88)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 7) {
                Text("FEATURED")
                    .font(.caption2.bold())
                    .foregroundStyle(Color.accentColor)
                Text(entry.displayName)
                    .font(.title.bold())
                Text(entry.summary)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                MarketplacePublisherLabel(publisher: entry.publisher)
            }
            Spacer(minLength: 16)
            VStack(alignment: .trailing, spacing: 10) {
                MarketplaceActionButton(
                    entry: entry,
                    installedVersion: installedVersion,
                    compatibility: compatibility,
                    operation: operation,
                    onInstall: onInstall
                )
                Button("View Details", action: onOpen)
                    .buttonStyle(.link)
            }
        }
        .padding(24)
        .marketplaceCardStyle(accented: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("marketplace.featured.\(entry.id.rawValue)")
    }
}

private struct MarketplaceExtensionCard: View {
    let entry: MarketplaceCatalogEntry
    let installedVersion: ExtensionVersion?
    let compatibility: MarketplaceCompatibilityState
    let operation: String?
    let onOpen: () -> Void
    let onInstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: entry.iconSystemName)
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 42, height: 42)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Button(entry.displayName, action: onOpen)
                        .buttonStyle(.plain)
                        .font(.headline)
                        .accessibilityHint("Open extension details")
                    MarketplacePublisherLabel(publisher: entry.publisher)
                }
                Spacer(minLength: 4)
                MarketplaceActionButton(
                    entry: entry,
                    installedVersion: installedVersion,
                    compatibility: compatibility,
                    operation: operation,
                    onInstall: onInstall
                )
            }
            Text(entry.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
            HStack {
                Label(entry.marketplaceCategory.rawValue, systemImage: "square.grid.2x2")
                Spacer()
                Text("Version \(entry.latest.version.description)")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(17)
        .marketplaceCardStyle()
        .accessibilityIdentifier("marketplace.extension.\(entry.id.rawValue)")
    }
}

struct MarketplaceInstallPresentation: Equatable {
    let title: String
    let isEnabled: Bool

    static func resolve(
        latestVersion: ExtensionVersion,
        installedVersion: ExtensionVersion?,
        compatibility: MarketplaceCompatibilityState,
        trust: MarketplaceTrustState,
        operation: String?
    ) -> MarketplaceInstallPresentation {
        let title: String
        if let operation {
            title = operation
        } else if let installedVersion {
            title = installedVersion < latestVersion
                ? String(localized: "Update")
                : String(localized: "Installed")
        } else {
            title = String(localized: "Get")
        }
        return MarketplaceInstallPresentation(
            title: title,
            isEnabled: operation == nil
                && title != "Installed"
                && compatibility == .compatible
                && trust == .trusted
        )
    }
}

private struct MarketplaceActionButton: View {
    let entry: MarketplaceCatalogEntry
    let installedVersion: ExtensionVersion?
    let compatibility: MarketplaceCompatibilityState
    let operation: String?
    let onInstall: () -> Void

    private var presentation: MarketplaceInstallPresentation {
        MarketplaceInstallPresentation.resolve(
            latestVersion: entry.latest.version,
            installedVersion: installedVersion,
            compatibility: compatibility,
            trust: MarketplaceReleaseEvaluator.trust(of: entry),
            operation: operation
        )
    }

    var body: some View {
        Button(action: onInstall) {
            Text(LocalizedStringKey(presentation.title))
        }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!presentation.isEnabled)
            .accessibilityLabel("\(presentation.title) \(entry.displayName)")
            .accessibilityHint(presentation.isEnabled ? "Opens installation confirmation" : disabledReason)
            .accessibilityIdentifier("marketplace.extension.\(entry.id.rawValue).action")
    }

    private var disabledReason: String {
        if case let .incompatible(reason) = compatibility { return reason }
        if case let .untrusted(reason) = MarketplaceReleaseEvaluator.trust(of: entry) { return reason }
        if presentation.title == "Installed" { return "This version is already installed." }
        return "An installation operation is in progress."
    }
}

private struct MarketplacePublisherLabel: View {
    let publisher: MarketplacePublisher

    var body: some View {
        Label(
            publisher.displayName,
            systemImage: publisher.verified ? "checkmark.seal.fill" : "person.crop.circle.badge.questionmark"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityLabel(publisher.verified
            ? "Verified publisher, \(publisher.displayName)"
            : "Unverified publisher, \(publisher.displayName)")
    }
}

private struct MarketplaceMessageCard: View {
    let icon: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(message).foregroundStyle(.secondary)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .padding(.top, 4)
                }
            }
            Spacer()
        }
        .padding(18)
        .marketplaceCardStyle()
    }
}

private extension View {
    func marketplaceCardStyle(accented: Bool = false) -> some View {
        background(
            accented ? AnyShapeStyle(Color.accentColor.opacity(0.07)) : AnyShapeStyle(.thinMaterial),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    accented ? Color.accentColor.opacity(0.28) : Color(nsColor: .separatorColor).opacity(0.6),
                    lineWidth: 1
                )
        }
    }
}

struct MarketplaceSample: Identifiable, Hashable {
    let id: String
    let name: String
    let publisher: String
    let summary: String
    let icon: String
    let category: MarketplaceCategory
    let features: [String]

    var allowsInstallation: Bool { false }

    static let samples = [
        MarketplaceSample(
            id: "sample.focus-deck",
            name: String(localized: "Focus Deck"),
            publisher: String(localized: "Sample Publisher"),
            summary: String(localized: "Keep timers and the next task close without leaving your workspace."),
            icon: "timer",
            category: .productivity,
            features: [
                String(localized: "Focus timer"),
                String(localized: "Task glance"),
                String(localized: "Quiet status"),
            ]
        ),
        MarketplaceSample(
            id: "sample.sound-stage",
            name: String(localized: "Sound Stage"),
            publisher: String(localized: "Sample Publisher"),
            summary: String(localized: "A compact audio workspace designed for the notch."),
            icon: "waveform",
            category: .media,
            features: [
                String(localized: "Now playing"),
                String(localized: "Audio levels"),
                String(localized: "Output status"),
            ]
        ),
        MarketplaceSample(
            id: "sample.system-pulse",
            name: String(localized: "System Pulse"),
            publisher: String(localized: "Sample Publisher"),
            summary: String(localized: "See a concise local snapshot of your Mac's activity."),
            icon: "gauge.with.dots.needle.50percent",
            category: .utilities,
            features: [
                String(localized: "Performance glance"),
                String(localized: "Storage status"),
                String(localized: "Local-only sample"),
            ]
        ),
    ]
}

private struct MarketplaceSampleCard: View {
    let sample: MarketplaceSample
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: sample.icon)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 42, height: 42)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Button(sample.name, action: onOpen)
                        .buttonStyle(.plain)
                        .font(.headline)
                    Text(sample.publisher).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("Preview only")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }
            Text(sample.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Label(sample.category.title, systemImage: "square.grid.2x2")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(17)
        .marketplaceCardStyle()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Local preview sample, \(sample.name). Not installable.")
        .accessibilityIdentifier("marketplace.sample.\(sample.id)")
    }
}

private struct MarketplaceSampleDetailsView: View {
    let sample: MarketplaceSample

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                MarketplaceDetailHero(
                    icon: sample.icon,
                    name: sample.name,
                    summary: sample.summary,
                    publisher: sample.publisher,
                    badge: "LOCAL PREVIEW"
                )
                MarketplaceMessageCard(
                    icon: "nosign",
                    title: "Sample content only",
                    message: "This preview is stored locally, is not a signed catalog entry, and cannot be installed."
                )
                MarketplaceScreenshotStrip(extensionName: sample.name)
                MarketplaceDetailSection(title: "Features") {
                    MarketplaceFeatureList(features: sample.features)
                }
                MarketplaceReviewPlaceholder()
                MarketplacePrivacyPlaceholder()
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(30)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(sample.name)
        .accessibilityIdentifier("marketplace.sample-detail.\(sample.id)")
    }
}

struct MarketplaceCatalogDetailsView: View {
    let entry: MarketplaceCatalogEntry
    let installedVersion: ExtensionVersion?
    let environment: MarketplaceHostEnvironment
    let operation: String?
    let onInstall: () -> Void

    private var compatibility: MarketplaceCompatibilityState {
        MarketplaceReleaseEvaluator.compatibility(of: entry.latest, with: environment)
    }

    private var trust: MarketplaceTrustState {
        MarketplaceReleaseEvaluator.trust(of: entry)
    }

    private var features: [String] {
        let capabilities = entry.latest.capabilities.map(displayName(for:))
        let actions = entry.latest.hostActions.map { displayName(for: $0.rawValue) }
        return Array(Set(capabilities + actions)).sorted()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                MarketplaceDetailHero(
                    icon: entry.iconSystemName,
                    name: entry.displayName,
                    summary: entry.summary,
                    publisher: entry.publisher.displayName,
                    badge: entry.publisher.verified ? "VERIFIED PUBLISHER" : "PUBLISHER"
                ) {
                    MarketplaceActionButton(
                        entry: entry,
                        installedVersion: installedVersion,
                        compatibility: compatibility,
                        operation: operation,
                        onInstall: onInstall
                    )
                    .controlSize(.large)
                }

                statusPanel
                MarketplaceScreenshotStrip(extensionName: entry.displayName)

                if features.isEmpty {
                    MarketplaceDetailSection(title: "Features") {
                        Text("No feature descriptions were provided in the signed catalog.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    MarketplaceDetailSection(title: "Features") {
                        MarketplaceFeatureList(features: features)
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    releaseDetails
                    permissionDetails
                }
                MarketplaceReviewPlaceholder()
                MarketplacePrivacyPlaceholder()
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(30)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(entry.displayName)
        .accessibilityIdentifier("marketplace.detail.\(entry.id.rawValue)")
    }

    private var statusPanel: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Trust").font(.headline)
                switch trust {
                case .trusted:
                    Label("Verified publisher and release", systemImage: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                case let .untrusted(reason):
                    Label(reason, systemImage: "exclamationmark.shield.fill")
                        .foregroundStyle(.orange)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Compatibility").font(.headline)
                switch compatibility {
                case .compatible:
                    Label("Compatible with this Mac", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case let .incompatible(reason):
                    Label(reason, systemImage: "xmark.circle.fill")
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
        }
        .padding(18)
        .marketplaceCardStyle()
        .accessibilityIdentifier("marketplace.detail.status")
    }

    private var releaseDetails: some View {
        MarketplaceDetailSection(title: "Release") {
            VStack(alignment: .leading, spacing: 9) {
                LabeledContent("Version", value: entry.latest.version.description)
                LabeledContent("Minimum macOS", value: entry.latest.compatibility.minimumMacOSVersion.description)
                LabeledContent("Signing team", value: entry.latest.teamIdentifier)
                LabeledContent(
                    "Architectures",
                    value: entry.latest.compatibility.supportedArchitectures.map(\.rawValue).sorted().joined(separator: ", ")
                )
                LabeledContent("Published") {
                    Text(entry.latest.publishedAt, style: .date)
                }
            }
            .font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var permissionDetails: some View {
        MarketplaceDetailSection(title: "Permissions") {
            if entry.latest.permissions.isEmpty {
                Text("None declared").foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(entry.latest.permissions.sorted(by: { $0.kind.rawValue < $1.kind.rawValue }), id: \.kind) { permission in
                        Label(
                            "\(displayName(for: permission.kind.rawValue)) · \(permission.required ? "Required" : "Optional")",
                            systemImage: permission.required ? "lock.fill" : "lock.open"
                        )
                    }
                }
                .font(.callout)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func displayName(for value: String) -> String {
        value.replacingOccurrences(of: "-", with: " ").capitalized
    }
}

private struct MarketplaceDetailHero<Action: View>: View {
    let icon: String
    let name: String
    let summary: String
    let publisher: String
    let badge: String
    @ViewBuilder let action: Action

    init(
        icon: String,
        name: String,
        summary: String,
        publisher: String,
        badge: String,
        @ViewBuilder action: () -> Action
    ) {
        self.icon = icon
        self.name = name
        self.summary = summary
        self.publisher = publisher
        self.badge = badge
        self.action = action()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 88, height: 88)
                .background(Color.accentColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 20))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(badge).font(.caption2.bold()).foregroundStyle(Color.accentColor)
                Text(name).font(.largeTitle.bold())
                Text(summary).font(.title3).foregroundStyle(.secondary)
                Text("By \(publisher)").font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            action
        }
    }
}

private extension MarketplaceDetailHero where Action == EmptyView {
    init(icon: String, name: String, summary: String, publisher: String, badge: String) {
        self.init(
            icon: icon,
            name: name,
            summary: summary,
            publisher: publisher,
            badge: badge,
            action: { EmptyView() }
        )
    }
}

private struct MarketplaceScreenshotStrip: View {
    let extensionName: String

    var body: some View {
        MarketplaceDetailSection(title: "Preview") {
            HStack(spacing: 14) {
                placeholder(number: 1)
                placeholder(number: 2)
            }
        }
    }

    private func placeholder(number: Int) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
            VStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                Text("Screenshot not provided")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.5))
        }
        .accessibilityLabel("\(extensionName) screenshot \(number) not provided")
    }
}

private struct MarketplaceFeatureList: View {
    let features: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), alignment: .leading)], alignment: .leading, spacing: 12) {
            ForEach(features, id: \.self) { feature in
                Label(feature, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.primary, Color.accentColor)
            }
        }
    }
}

private struct MarketplaceDetailSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    init(title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2.bold())
            content
        }
    }
}

private struct MarketplaceReviewPlaceholder: View {
    var body: some View {
        MarketplaceDetailSection(title: "Ratings & Reviews") {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No rating")
                        .font(.title3.bold())
                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { _ in
                            Image(systemName: "star")
                        }
                    }
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("No rating available")
                }
                Divider()
                Text("Ratings and reviews are not included in the signed Marketplace catalog yet.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(18)
            .marketplaceCardStyle()
        }
        .accessibilityIdentifier("marketplace.detail.reviews")
    }
}

private struct MarketplacePrivacyPlaceholder: View {
    var body: some View {
        MarketplaceDetailSection(title: "Privacy") {
            HStack(spacing: 10) {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(Color.accentColor)
                Text("A publisher privacy-policy link was not provided in this catalog.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Privacy Policy") {}
                    .disabled(true)
                    .accessibilityHint("No privacy policy link is available")
            }
            .padding(18)
            .marketplaceCardStyle()
        }
        .accessibilityIdentifier("marketplace.detail.privacy")
    }
}

private struct MarketplaceUnavailableDetailView: View {
    var body: some View {
        MarketplaceMessageCard(
            icon: "questionmark.circle",
            title: "Extension unavailable",
            message: "This extension is no longer present in the current verified catalog."
        )
        .padding(30)
        .navigationTitle("Unavailable")
    }
}

struct MarketplaceInstallConfirmation: View {
    let entry: MarketplaceCatalogEntry
    let isUpdate: Bool
    let onCancel: () -> Void
    let onInstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(
                isUpdate ? "Update \(entry.displayName)?" : "Install \(entry.displayName)?",
                systemImage: entry.iconSystemName
            )
            .font(.title2.bold())
            Text("Version \(entry.latest.version.description) by \(entry.publisher.displayName)")
                .foregroundStyle(.secondary)
            Label(
                "Verified publisher, Developer ID signature, notarization, and stapled ticket are required.",
                systemImage: "checkmark.shield"
            )
            if !entry.latest.permissions.isEmpty {
                Text("Declared permissions: \(entry.latest.permissions.map(\.kind.rawValue).sorted().joined(separator: ", ")).")
                    .font(.callout)
            }
            Text("Installing does not grant permissions or macOS approval. Those remain separate system decisions.")
                .font(.callout)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("marketplace.install.cancel")
                Button(isUpdate ? "Update" : "Install", action: onInstall)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("marketplace.install.confirm")
            }
        }
        .padding(24)
        .frame(width: 560)
        .accessibilityIdentifier("marketplace.install-confirmation")
    }
}
