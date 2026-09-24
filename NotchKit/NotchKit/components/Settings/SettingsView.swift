//
//  SettingsView.swift
//  NotchKit
//
//  Settings window for General, Appearance, Interaction, Extensions,
//  Marketplace, Shortcuts, and About. Feature configuration lives under Extensions via the
//  authoritative settings catalog; `Advanced` no longer exists.
//

import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import NotchExtensionSDK
import Sparkle
import SwiftUI

struct SettingsView: View {
    @State private var selectedSection: SettingsSection?
    @State private var shortcutsOwner: ShortcutsOwner? = nil
    @State private var marketplaceSelection: ExtensionIdentity?
    @State private var accentColorUpdateTrigger = UUID()

    let updaterController: SPUStandardUpdaterController?

    init(
        updaterController: SPUStandardUpdaterController? = nil,
        initialSection: SettingsSection = .general
    ) {
        self.updaterController = updaterController
        _selectedSection = State(initialValue: initialSection)
    }

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(selection: sidebarSelection)
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(min: 210, ideal: 226, max: 250)
        } detail: {
            Group {
                switch selectedSection ?? .general {
                case .general:
                    GeneralSettings()
                case .appearance:
                    AppearanceSettings()
                case .interaction:
                    InteractionSettings()
                case .extensions:
                    ExtensionsSettingsView(
                        onOpenShortcuts: { owner in
                            shortcutsOwner = owner
                            selectedSection = .shortcuts
                        },
                        onOpenMarketplace: { extensionID in
                            marketplaceSelection = extensionID
                            selectedSection = .marketplace
                        }
                    )
                case .marketplace:
                    MarketplaceSettingsHost(initialSelection: marketplaceSelection)
                case .shortcuts:
                    ShortcutsSettings(owner: shortcutsOwner)
                case .about:
                    aboutView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("")
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        .formStyle(.grouped)
        .background(Color(NSColor.windowBackgroundColor))
        .tint(.effectiveAccent)
        .id(accentColorUpdateTrigger)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AccentColorChanged"))) { _ in
            accentColorUpdateTrigger = UUID()
        }
    }

    @ViewBuilder
    private var aboutView: some View {
        if let controller = updaterController {
            About(updaterController: controller)
        } else {
            About(
                updaterController: SPUStandardUpdaterController(
                    startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil))
        }
    }

    /// Selecting Shortcuts from the sidebar clears any temporary owner focus
    /// left over from a feature link. Feature links set `selectedSection`
    /// directly, so their focus is preserved.
    private var sidebarSelection: Binding<SettingsSection?> {
        Binding(
            get: { selectedSection },
            set: { newValue in
                if newValue == .shortcuts {
                    shortcutsOwner = nil
                }
                if newValue == .marketplace {
                    marketplaceSelection = nil
                }
                selectedSection = newValue
            }
        )
    }
}

private struct SettingsSidebar: View {
    @Binding var selection: SettingsSection?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image("NotchKitBrand")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .accessibilityHidden(true)

                Text("NotchKit")
                    .font(.title2.bold())
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 28)

            VStack(spacing: 6) {
                ForEach(SettingsSection.allCases) { section in
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                            selection = section
                        }
                    } label: {
                        HStack(spacing: 13) {
                            Image(systemName: section.systemImage)
                                .font(.body.weight(.medium))
                                .frame(width: 24)
                            Text(section.title)
                                .font(.body.weight(.medium))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(selection == section ? Color.white : Color.primary)
                        .padding(.horizontal, 14)
                        .frame(height: 42)
                        .background {
                            if selection == section {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Color.effectiveAccent.gradient)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.sidebar.\(section.rawValue)")
                    .accessibilityValue(selection == section ? "Selected" : "")
                }
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 24)

            Divider()
                .padding(.horizontal, 18)

            Text("Make more of your notch.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
        }
        .background(.ultraThinMaterial)
        .accessibilityIdentifier("settings.sidebar")
    }
}

private struct MarketplaceSettingsHost: View {
    let initialSelection: ExtensionIdentity?
    @ObservedObject private var localExtensions = NotchKitRuntime.shared.localExtensions
    @ObservedObject private var marketplace = NotchKitRuntime.shared.marketplace
    @State private var operationError: String?

    private var installedVersions: [ExtensionIdentity: ExtensionVersion] {
        Dictionary(uniqueKeysWithValues: localExtensions.installed.map {
            ($0.id, $0.record.extensionVersion)
        })
    }

    private var environment: MarketplaceHostEnvironment {
        let rawVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let hostVersion = rawVersion.flatMap(ExtensionVersion.init)
            ?? ExtensionVersion(major: 1, minor: 0, patch: 0)
        return .current(hostVersion: hostVersion)
    }

    var body: some View {
        MarketplaceSettingsView(
            marketplace: marketplace,
            installedVersions: installedVersions,
            environment: environment,
            initialSelection: initialSelection,
            onInstall: install
        )
        .navigationTitle("Marketplace")
        .alert("Marketplace Error", isPresented: Binding(
            get: { operationError != nil },
            set: { if !$0 { operationError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(operationError ?? "Unknown error")
        }
    }

    private func install(_ entry: MarketplaceCatalogEntry) {
        guard authorizeManagedLocationIfNeeded() else { return }
        guard #available(macOS 26.0, *) else { return }
        Task {
            do {
                try await marketplace.install(
                    entry,
                    environment: environment,
                    localExtensions: localExtensions
                )
            } catch {
                operationError = error.localizedDescription
            }
        }
    }

    private func authorizeManagedLocationIfNeeded() -> Bool {
        guard !localExtensions.hasManagedLocationAccess else { return true }
        let panel = NSOpenPanel()
        panel.title = "Allow Extension Installation"
        panel.message = "Choose this LocalExtensions folder so NotchKit can install signed extensions."
        panel.prompt = "Allow"
        panel.directoryURL = localExtensions.rootURL
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try localExtensions.authorizeManagedLocation(at: url)
            return true
        } catch {
            operationError = error.localizedDescription
            return false
        }
    }
}

// MARK: - Shared shell

private struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(_ title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.largeTitle.bold())
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)

                content
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 30)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .background(SettingsPalette.canvas.ignoresSafeArea())
        .navigationTitle(title)
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let content: Content

    init(
        _ title: String,
        subtitle: String? = nil,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.effectiveAccent)
                    .frame(width: 28, height: 28)
                    .background(Color.effectiveAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(18)

            Divider()
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(18)
        }
        .background(SettingsPalette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(SettingsPalette.border, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }
}

private enum SettingsPalette {
    static let canvas = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.075, green: 0.082, blue: 0.09, alpha: 1)
                : NSColor(srgbRed: 0.945, green: 0.958, blue: 0.97, alpha: 1)
        })
    static let card = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.115, green: 0.122, blue: 0.13, alpha: 1)
                : NSColor(srgbRed: 0.99, green: 0.995, blue: 1, alpha: 1)
        })
    static let border = Color.primary.opacity(0.11)
}

// MARK: - General

struct GeneralSettings: View {
    @State private var screens: [(uuid: String, name: String)] = NSScreen.screens.compactMap { screen in
        guard let uuid = screen.displayUUID else { return nil }
        return (uuid, screen.localizedName)
    }
    @ObservedObject var coordinator = BoringViewCoordinator.shared

    @Default(.showOnAllDisplays) var showOnAllDisplays
    @Default(.automaticallySwitchDisplay) var automaticallySwitchDisplay

    var body: some View {
        SettingsPage(
            String(localized: "General"),
            subtitle: String(localized: "Choose how NotchKit starts and where it appears.")
        ) {
            SettingsCard(
                String(localized: "System features"),
                subtitle: String(localized: "Startup, menu bar, and display preferences."),
                systemImage: "macwindow"
            ) {
                Toggle(isOn: Binding(
                    get: { Defaults[.menubarIcon] },
                    set: { Defaults[.menubarIcon] = $0 }
                )) {
                    Text("Show menu bar icon")
                }
                .tint(.effectiveAccent)
                LaunchAtLogin.Toggle("Launch at login")
                Defaults.Toggle(key: .showOnAllDisplays) {
                    Text("Show on all displays")
                }
                .onChange(of: showOnAllDisplays) {
                    NotificationCenter.default.post(
                        name: Notification.Name.showOnAllDisplaysChanged, object: nil)
                }
                Divider()
                Picker("Preferred display", selection: $coordinator.preferredScreenUUID) {
                    ForEach(screens, id: \.uuid) { screen in
                        Text(screen.name).tag(screen.uuid as String?)
                    }
                }
                .onChange(of: NSScreen.screens) {
                    screens = NSScreen.screens.compactMap { screen in
                        guard let uuid = screen.displayUUID else { return nil }
                        return (uuid, screen.localizedName)
                    }
                }
                .disabled(showOnAllDisplays)
                .accessibilityLabel("Preferred display")

                Divider()
                Defaults.Toggle(key: .automaticallySwitchDisplay) {
                    Text("Automatically switch displays")
                }
                .onChange(of: automaticallySwitchDisplay) {
                    NotificationCenter.default.post(
                        name: Notification.Name.automaticallySwitchDisplayChanged, object: nil)
                }
                .disabled(showOnAllDisplays)
            }
        }
        .toolbar {
            Button("Quit app") {
                NSApp.terminate(self)
            }
            .controlSize(.extraLarge)
        }
        .tint(.effectiveAccent)
    }
}

// MARK: - Interaction

struct InteractionSettings: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared

    @Default(.gestureSensitivity) var gestureSensitivity
    @Default(.minimumHoverDuration) var minimumHoverDuration
    @Default(.openNotchOnHover) var openNotchOnHover
    @Default(.extendHoverArea) var extendHoverArea
    @Default(.enableGestures) var enableGestures

    var body: some View {
        SettingsPage(
            String(localized: "Interaction"),
            subtitle: String(localized: "Tune how the notch responds to your pointer and gestures.")
        ) {
            SettingsCard(
                String(localized: "Notch behavior"),
                subtitle: String(localized: "Control automatic opening and feedback."),
                systemImage: "hand.point.up.left"
            ) {
                Defaults.Toggle(key: .openNotchOnHover) {
                    Text("Open notch on hover")
                }
                Defaults.Toggle(key: .enableHaptics) {
                    Text("Enable haptic feedback")
                }
                Toggle("Remember last tab", isOn: $coordinator.openLastTabByDefault)
                Defaults.Toggle(key: .extendHoverArea) {
                    Text("Extend hover area")
                }
                if openNotchOnHover {
                    VStack(spacing: 8) {
                        HStack {
                            Text("Hover delay")
                            Spacer()
                            Text("\(minimumHoverDuration, specifier: "%.1f")s")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $minimumHoverDuration, in: 0...1, step: 0.1)
                            .labelsHidden()
                    }
                    .onChange(of: minimumHoverDuration) {
                        NotificationCenter.default.post(
                            name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
            }

            gestureControls
        }
        .tint(.effectiveAccent)
        .onChange(of: openNotchOnHover) {
            if !openNotchOnHover {
                enableGestures = true
            }
        }
    }

    @ViewBuilder
    private var gestureControls: some View {
        SettingsCard(
            String(localized: "Gesture control"),
            subtitle: String(localized: "Use two-finger gestures directly over the notch."),
            systemImage: "hand.draw"
        ) {
            Defaults.Toggle(key: .enableGestures) {
                Text("Enable gestures")
            }
            .disabled(!openNotchOnHover)
            if enableGestures {
                Toggle("Change media with horizontal gestures", isOn: .constant(false))
                    .disabled(true)
                Defaults.Toggle(key: .closeGestureEnabled) {
                    Text("Close gesture")
                }
                VStack(spacing: 8) {
                    HStack {
                        Text("Gesture sensitivity")
                        Spacer()
                        Text(
                            SettingsBehavior.gestureSensitivityLabel(for: gestureSensitivity)
                        )
                        .foregroundStyle(.secondary)
                    }
                    Slider(value: $gestureSensitivity, in: 100...300, step: 100)
                        .labelsHidden()
                }
            }
            HStack {
                customBadge(text: "Beta")
                Spacer()
            }
            Text(
                "Two-finger swipe up on notch to close, two-finger swipe down on notch to open when **Open notch on hover** option is disabled"
            )
            .foregroundStyle(.secondary)
            .font(.caption)
        }
    }
}

// MARK: - Appearance

struct AppearanceSettings: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared

    @Default(.nonNotchHeight) var nonNotchHeight
    @Default(.nonNotchHeightMode) var nonNotchHeightMode
    @Default(.notchHeight) var notchHeight
    @Default(.notchHeightMode) var notchHeightMode

    @Default(.useCustomAccentColor) var useCustomAccentColor
    @Default(.customAccentColorData) var customAccentColorData
    @Default(.showOnLockScreen) var showOnLockScreen
    @Default(.hideFromScreenRecording) var hideFromScreenRecording

    @State private var customAccentColor: Color = .accentColor
    @State private var selectedPresetColor: PresetAccentColor? = nil

    enum PresetAccentColor: String, CaseIterable, Identifiable {
        case blue = "Blue"
        case purple = "Purple"
        case pink = "Pink"
        case red = "Red"
        case orange = "Orange"
        case yellow = "Yellow"
        case green = "Green"
        case graphite = "Graphite"

        var id: String { self.rawValue }

        var color: Color {
            switch self {
            case .blue: return Color(red: 0.0, green: 0.478, blue: 1.0)
            case .purple: return Color(red: 0.686, green: 0.322, blue: 0.871)
            case .pink: return Color(red: 1.0, green: 0.176, blue: 0.333)
            case .red: return Color(red: 1.0, green: 0.271, blue: 0.227)
            case .orange: return Color(red: 1.0, green: 0.584, blue: 0.0)
            case .yellow: return Color(red: 1.0, green: 0.8, blue: 0.0)
            case .green: return Color(red: 0.4, green: 0.824, blue: 0.176)
            case .graphite: return Color(red: 0.557, green: 0.557, blue: 0.576)
            }
        }
    }

    var body: some View {
        SettingsPage(
            String(localized: "Appearance"),
            subtitle: String(localized: "Shape the notch and make NotchKit feel at home on your Mac.")
        ) {
            SettingsCard(String(localized: "Interface"), systemImage: "rectangle.3.group") {
                Toggle("Always show tabs", isOn: $coordinator.alwaysShowTabs)
                Defaults.Toggle(key: .settingsIconInNotch) {
                    Text("Show settings icon in notch")
                }
            }

            SettingsCard(
                String(localized: "Notch sizing"),
                subtitle: String(localized: "Set the closed height for each display type."),
                systemImage: "arrow.up.and.down"
            ) {
                Picker(
                    selection: $notchHeightMode,
                    label: Text("Notch height on notch displays")
                ) {
                    Text("Match real notch height").tag(WindowHeightMode.matchRealNotchSize)
                    Text("Match menu bar height").tag(WindowHeightMode.matchMenuBar)
                    Text("Custom height").tag(WindowHeightMode.custom)
                }
                .onChange(of: notchHeightMode) {
                    switch notchHeightMode {
                    case .matchRealNotchSize: notchHeight = 38
                    case .matchMenuBar: notchHeight = 44
                    case .custom: notchHeight = 38
                    }
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
                if notchHeightMode == .custom {
                    Slider(value: $notchHeight, in: 15...45, step: 1) {
                        Text("Custom notch size - \(notchHeight, specifier: "%.0f")")
                    }
                    .onChange(of: notchHeight) {
                        NotificationCenter.default.post(
                            name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
                Picker("Notch height on non-notch displays", selection: $nonNotchHeightMode) {
                    Text("Match menubar height").tag(WindowHeightMode.matchMenuBar)
                    Text("Match real notch height").tag(WindowHeightMode.matchRealNotchSize)
                    Text("Custom height").tag(WindowHeightMode.custom)
                }
                .onChange(of: nonNotchHeightMode) {
                    switch nonNotchHeightMode {
                    case .matchMenuBar: nonNotchHeight = 24
                    case .matchRealNotchSize: nonNotchHeight = 32
                    case .custom: nonNotchHeight = 32
                    }
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
                if nonNotchHeightMode == .custom {
                    Slider(value: $nonNotchHeight, in: 0...40, step: 1) {
                        Text("Custom notch size - \(nonNotchHeight, specifier: "%.0f")")
                    }
                    .onChange(of: nonNotchHeight) {
                        NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
            }

            SettingsCard(String(localized: "Animations"), systemImage: "sparkles") {
                Defaults.Toggle(key: .showNotHumanFace) {
                    Text("Show cool face animation while inactive")
                }
            }

            accentColorSection

            SettingsCard(String(localized: "Window appearance"), systemImage: "macwindow") {
                Defaults.Toggle(key: .enableShadow) {
                    Text("Enable window shadow")
                }
                Defaults.Toggle(key: .cornerRadiusScaling) {
                    Text("Corner radius scaling")
                }
            }

            SettingsCard(String(localized: "Window behavior"), systemImage: "lock.shield") {
                Defaults.Toggle(key: .hideTitleBar) {
                    Text("Hide title bar")
                }
                Defaults.Toggle(key: .showOnLockScreen) {
                    Text("Show notch on lock screen")
                }
                Defaults.Toggle(key: .hideFromScreenRecording) {
                    Text("Hide from screen recording")
                }
            }

        }
        .tint(.effectiveAccent)
        .onAppear {
            loadCustomColor()
        }
    }

    @ViewBuilder
    private var accentColorSection: some View {
        SettingsCard(
            String(localized: "Accent color"),
            subtitle: String(localized: "Use the macOS accent or choose a NotchKit color."),
            systemImage: "paintpalette"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Accent color", selection: $useCustomAccentColor) {
                    Text("System").tag(false)
                    Text("Custom").tag(true)
                }
                .pickerStyle(.segmented)

                if !useCustomAccentColor {
                    HStack(spacing: 12) {
                        AccentCircleButton(
                            isSelected: true,
                            color: .accentColor,
                            isSystemDefault: true,
                            accessibilityName: "System accent color"
                        ) {}
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Using System Accent").font(.body)
                            Text("Your macOS system accent color")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Color Presets")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            ForEach(PresetAccentColor.allCases) { preset in
                                AccentCircleButton(
                                    isSelected: selectedPresetColor == preset,
                                    color: preset.color,
                                    accessibilityName: "\(preset.rawValue) accent color"
                                ) {
                                    selectedPresetColor = preset
                                    customAccentColor = preset.color
                                    saveCustomColor(preset.color)
                                    forceUiUpdate()
                                }
                            }
                            Spacer()
                        }
                        Divider().padding(.vertical, 4)
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Pick a Color").font(.body)
                                Text("Choose any color")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            ColorPicker(selection: Binding(
                                get: { customAccentColor },
                                set: { newColor in
                                    customAccentColor = newColor
                                    selectedPresetColor = nil
                                    saveCustomColor(newColor)
                                    forceUiUpdate()
                                }
                            ), supportsOpacity: false) {
                                ZStack {
                                    Circle().fill(customAccentColor).frame(width: 32, height: 32)
                                    if selectedPresetColor == nil {
                                        Circle()
                                            .strokeBorder(.primary.opacity(0.3), lineWidth: 2)
                                            .frame(width: 32, height: 32)
                                    }
                                }
                            }
                            .labelsHidden()
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func forceUiUpdate() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("AccentColorChanged"), object: nil)
        }
    }

    private func saveCustomColor(_ color: Color) {
        let nsColor = NSColor(color)
        if let colorData = try? NSKeyedArchiver.archivedData(
            withRootObject: nsColor, requiringSecureCoding: false
        ) {
            Defaults[.customAccentColorData] = colorData
            forceUiUpdate()
        }
    }

    private func loadCustomColor() {
        if let colorData = Defaults[.customAccentColorData],
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
            customAccentColor = Color(nsColor: nsColor)
            selectedPresetColor = nil
            for preset in PresetAccentColor.allCases {
                if colorsAreEqual(Color(nsColor: nsColor), preset.color) {
                    selectedPresetColor = preset
                    break
                }
            }
        }
    }

    private func colorsAreEqual(_ color1: Color, _ color2: Color) -> Bool {
        let nsColor1 = NSColor(color1).usingColorSpace(.sRGB) ?? NSColor(color1)
        let nsColor2 = NSColor(color2).usingColorSpace(.sRGB) ?? NSColor(color2)
        return abs(nsColor1.redComponent - nsColor2.redComponent) < 0.01 &&
            abs(nsColor1.greenComponent - nsColor2.greenComponent) < 0.01 &&
            abs(nsColor1.blueComponent - nsColor2.blueComponent) < 0.01
    }
}

// MARK: - About

struct About: View {
    @State private var showBuildNumber: Bool = false
    let updaterController: SPUStandardUpdaterController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SettingsPage(
            String(localized: "About"),
            subtitle: String(localized: "NotchKit makes the space around your notch more useful.")
        ) {
            HStack(spacing: 18) {
                Image("NotchKitBrand")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("NotchKit")
                        .font(.title.bold())
                    Text("Make more of your notch.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)

            SettingsCard(String(localized: "Version info"), systemImage: "info.circle") {
                HStack {
                    Text("Release name")
                    Spacer()
                    Text(Defaults[.releaseName])
                        .foregroundStyle(.secondary)
                }
                Divider()
                Button {
                    withAnimation(reduceMotion ? nil : .default) { showBuildNumber.toggle() }
                } label: {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(versionDescription)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows or hides the build number")
            }

            SettingsCard(
                String(localized: "Software updates"),
                subtitle: String(localized: "Update delivery is not configured for this build."),
                systemImage: "arrow.triangle.2.circlepath"
            ) {
                Text("Automatic updates are disabled until a NotchKit update feed and signing key are configured.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Toggle("Automatically check for updates", isOn: .constant(false))
                    .disabled(true)
                Toggle("Automatically download updates", isOn: .constant(false))
                    .disabled(true)
            }

            SettingsCard(String(localized: "Community"), systemImage: "person.3") {
                Button {
                    if let url = URL(string: "https://github.com/TheBoredTeam/boring.notch") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Open NotchKit on GitHub", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens GitHub in your default browser")
            }

            Text("Made with care by not so boring not.people")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
        }
        .toolbar {
            CheckForUpdatesView(updater: updaterController.updater)
        }
    }

    private var versionDescription: String {
        let version = Bundle.main.releaseVersionNumber ?? "unknown"
        guard showBuildNumber else { return version }
        return "\(version) (\(Bundle.main.buildVersionNumber ?? "unknown"))"
    }
}

// MARK: - Shortcuts

struct ShortcutsSettings: View {
    /// When set, the owner's group is scrolled into view and marked.
    let owner: ShortcutsOwner?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            SettingsPage(
                String(localized: "Shortcuts"),
                subtitle: String(localized: "Keep your most-used NotchKit actions within reach.")
            ) {
                ForEach(ShortcutsOwner.ordered(focused: owner), id: \.self) { sectionOwner in
                    SettingsCard(
                        sectionOwner.title,
                        subtitle: sectionOwner == .media
                            ? String(localized: "Control media without opening the notch.")
                            : String(localized: "Open or close NotchKit from anywhere."),
                        systemImage: sectionOwner == .media ? "music.note" : "rectangle.topthird.inset.filled"
                    ) {
                        switch sectionOwner {
                        case .media:
                            KeyboardShortcuts.Recorder(
                                "Toggle Sneak Peek:", name: .toggleSneakPeek)
                        case .notch:
                            KeyboardShortcuts.Recorder(
                                "Toggle Notch Open:", name: .toggleNotchOpen)
                        }
                        if owner == sectionOwner {
                            HStack {
                                customBadge(text: "Focused")
                                Spacer()
                            }
                        }
                        if sectionOwner == .media {
                            Text("Sneak Peek shows the media title and artist under the notch for a few seconds.")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                    .id(sectionOwner)
                }
            }
            .onAppear {
                guard let owner else { return }
                DispatchQueue.main.async {
                    withAnimation(reduceMotion ? nil : .default) {
                        proxy.scrollTo(owner, anchor: .top)
                    }
                }
            }
        }
        .tint(.effectiveAccent)
    }

}

// MARK: - Components

struct AccentCircleButton: View {
    let isSelected: Bool
    let color: Color
    var isSystemDefault: Bool = false
    var isMulticolor: Bool = false
    var accessibilityName: String = "Accent color"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(color).frame(width: 32, height: 32)
                Circle()
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                    .frame(width: 32, height: 32)
                if isSelected {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.5), lineWidth: 2)
                        .frame(width: 28, height: 28)
                }
            }
        }
        .buttonStyle(.plain)
        .help(isSystemDefault ? "Use your macOS system accent color" : "")
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(isSelected ? "Selected" : "")
    }
}

func lighterColor(from nsColor: NSColor, amount: CGFloat = 0.14) -> Color {
    let srgb = nsColor.usingColorSpace(.sRGB) ?? nsColor
    var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
    srgb.getRed(&r, green: &g, blue: &b, alpha: &a)

    func lighten(_ c: CGFloat) -> CGFloat {
        let increased = c + (1.0 - c) * amount
        return min(max(increased, 0), 1)
    }

    return Color(
        red: Double(lighten(r)),
        green: Double(lighten(g)),
        blue: Double(lighten(b)),
        opacity: Double(a)
    )
}

func proFeatureBadge() -> some View {
    Text("Upgrade to Pro")
        .foregroundStyle(Color(red: 0.545, green: 0.196, blue: 0.98))
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 4).stroke(
                Color(red: 0.545, green: 0.196, blue: 0.98), lineWidth: 1))
}

func comingSoonTag() -> some View {
    Text("Coming soon")
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

func customBadge(text: LocalizedStringKey) -> some View {
    Text(text)
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

func warningBadge(_ text: String, _ description: String) -> some View {
    Section {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.yellow)
            VStack(alignment: .leading) {
                Text(text).font(.headline)
                Text(description).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
