//
//  SettingsView.swift
//  NotchKit
//
//  Six-section Settings window: General, Appearance, Interaction, Extensions,
//  Shortcuts, and About. Feature configuration lives under Extensions via the
//  authoritative settings catalog; `Advanced` no longer exists.
//

import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import Sparkle
import SwiftUI

struct SettingsView: View {
    @State private var selectedSection: SettingsSection? = .general
    @State private var shortcutsOwner: ShortcutsOwner? = nil
    @State private var accentColorUpdateTrigger = UUID()

    let updaterController: SPUStandardUpdaterController?

    init(updaterController: SPUStandardUpdaterController? = nil) {
        self.updaterController = updaterController
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                ForEach(SettingsSection.allCases) { section in
                    NavigationLink(value: section) {
                        Label(section.title, systemImage: section.systemImage)
                    }
                }
            }
            .listStyle(SidebarListStyle())
            .tint(.effectiveAccent)
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
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
                    ExtensionsSettingsView { owner in
                        shortcutsOwner = owner
                        selectedSection = .shortcuts
                    }
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
        Form {
            Section {
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

                Defaults.Toggle(key: .automaticallySwitchDisplay) {
                    Text("Automatically switch displays")
                }
                .onChange(of: automaticallySwitchDisplay) {
                    NotificationCenter.default.post(
                        name: Notification.Name.automaticallySwitchDisplayChanged, object: nil)
                }
                .disabled(showOnAllDisplays)
            } header: {
                Text("System features")
            }
        }
        .toolbar {
            Button("Quit app") {
                NSApp.terminate(self)
            }
            .controlSize(.extraLarge)
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("General")
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
        Form {
            Section {
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
                    Slider(value: $minimumHoverDuration, in: 0...1, step: 0.1) {
                        HStack {
                            Text("Hover delay")
                            Spacer()
                            Text("\(minimumHoverDuration, specifier: "%.1f")s")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: minimumHoverDuration) {
                        NotificationCenter.default.post(
                            name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
            } header: {
                Text("Notch behavior")
            }

            gestureControls
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Interaction")
        .onChange(of: openNotchOnHover) {
            if !openNotchOnHover {
                enableGestures = true
            }
        }
    }

    @ViewBuilder
    private var gestureControls: some View {
        Section {
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
                Slider(value: $gestureSensitivity, in: 100...300, step: 100) {
                    HStack {
                        Text("Gesture sensitivity")
                        Spacer()
                        Text(
                            Defaults[.gestureSensitivity] == 100
                                ? "High" : Defaults[.gestureSensitivity] == 200 ? "Medium" : "Low"
                        )
                        .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            HStack {
                Text("Gesture control")
                customBadge(text: "Beta")
            }
        } footer: {
            Text(
                "Two-finger swipe up on notch to close, two-finger swipe down on notch to open when **Open notch on hover** option is disabled"
            )
            .multilineTextAlignment(.trailing)
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
    let icons: [String] = ["logo2"]
    @State private var selectedIcon: String = "logo2"

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
        Form {
            Section {
                Toggle("Always show tabs", isOn: $coordinator.alwaysShowTabs)
                Defaults.Toggle(key: .settingsIconInNotch) {
                    Text("Show settings icon in notch")
                }
            } header: {
                Text("General")
            }

            Section {
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
            } header: {
                Text("Notch sizing")
            }

            Section {
                Defaults.Toggle(key: .showNotHumanFace) {
                    Text("Show cool face animation while inactive")
                }
            } header: {
                Text("Animations")
            }

            accentColorSection

            Section {
                Defaults.Toggle(key: .enableShadow) {
                    Text("Enable window shadow")
                }
                Defaults.Toggle(key: .cornerRadiusScaling) {
                    Text("Corner radius scaling")
                }
            } header: {
                Text("Window Appearance")
            }

            Section {
                Defaults.Toggle(key: .hideTitleBar) {
                    Text("Hide title bar")
                }
                Defaults.Toggle(key: .showOnLockScreen) {
                    Text("Show notch on lock screen")
                }
                Defaults.Toggle(key: .hideFromScreenRecording) {
                    Text("Hide from screen recording")
                }
            } header: {
                Text("Window Behavior")
            }

            appIconSection
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Appearance")
        .onAppear {
            loadCustomColor()
        }
    }

    @ViewBuilder
    private var accentColorSection: some View {
        Section {
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
                            isSystemDefault: true
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
                                    isMulticolor: false
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
        } header: {
            Text("Accent color")
        } footer: {
            Text("Choose between your system accent color or customize it with your own selection.")
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    @ViewBuilder
    private var appIconSection: some View {
        Section {
            HStack {
                ForEach(icons, id: \.self) { icon in
                    Spacer()
                    VStack {
                        Image(icon)
                            .resizable()
                            .frame(width: 80, height: 80)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .circular)
                                    .strokeBorder(
                                        icon == selectedIcon ? Color.effectiveAccent : .clear,
                                        lineWidth: 2.5
                                    )
                            )
                        Text("Default")
                            .fontWeight(.medium)
                            .font(.caption)
                            .foregroundStyle(icon == selectedIcon ? .white : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(icon == selectedIcon ? Color.effectiveAccent : .clear)
                            )
                    }
                    .onTapGesture {
                        withAnimation { selectedIcon = icon }
                        NSApp.applicationIconImage = NSImage(named: icon)
                    }
                    Spacer()
                }
            }
            .disabled(true)
        } header: {
            HStack {
                Text("App icon")
                customBadge(text: "Coming soon")
            }
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
    @Environment(\.openWindow) var openWindow
    var body: some View {
        VStack {
            Form {
                Section {
                    HStack {
                        Text("Release name")
                        Spacer()
                        Text(Defaults[.releaseName])
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Version")
                        Spacer()
                        if showBuildNumber {
                            Text("(\(Bundle.main.buildVersionNumber ?? ""))")
                                .foregroundStyle(.secondary)
                        }
                        Text(Bundle.main.releaseVersionNumber ?? "unkown")
                            .foregroundStyle(.secondary)
                    }
                    .onTapGesture {
                        withAnimation { showBuildNumber.toggle() }
                    }
                } header: {
                    Text("Version info")
                }

                UpdaterSettingsView(updater: updaterController.updater)

                HStack(spacing: 30) {
                    Spacer(minLength: 0)
                    Button {
                        if let url = URL(string: "https://github.com/TheBoredTeam/boring.notch") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        VStack(spacing: 5) {
                            Image("Github")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 18)
                            Text("GitHub")
                        }
                        .contentShape(Rectangle())
                    }
                    Spacer(minLength: 0)
                }
                .buttonStyle(PlainButtonStyle())
            }
            VStack(spacing: 0) {
                Divider()
                Text("Made with 🫶🏻 by not so boring not.people")
                    .foregroundStyle(.secondary)
                    .padding(.top, 5)
                    .padding(.bottom, 7)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .toolbar {
            CheckForUpdatesView(updater: updaterController.updater)
        }
        .navigationTitle("About")
    }
}

// MARK: - Shortcuts

struct ShortcutsSettings: View {
    /// When set, the owner's group is scrolled into view and marked.
    let owner: ShortcutsOwner?

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                ForEach(orderedOwners, id: \.self) { sectionOwner in
                    Section {
                        switch sectionOwner {
                        case .media:
                            KeyboardShortcuts.Recorder(
                                "Toggle Sneak Peek:", name: .toggleSneakPeek)
                        case .notch:
                            KeyboardShortcuts.Recorder(
                                "Toggle Notch Open:", name: .toggleNotchOpen)
                        }
                    } header: {
                        HStack {
                            Text(sectionOwner.title)
                            if owner == sectionOwner {
                                customBadge(text: "Focused")
                            }
                        }
                    } footer: {
                        if sectionOwner == .media {
                            Text("Sneak Peek shows the media title and artist under the notch for a few seconds.")
                                .multilineTextAlignment(.trailing)
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
                    withAnimation { proxy.scrollTo(owner, anchor: .top) }
                }
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Shortcuts")
    }

    /// Focused owner first, then the remaining owners in declaration order.
    private var orderedOwners: [ShortcutsOwner] {
        guard let owner else { return ShortcutsOwner.allCases }
        return [owner] + ShortcutsOwner.allCases.filter { $0 != owner }
    }
}

// MARK: - Components

struct AccentCircleButton: View {
    let isSelected: Bool
    let color: Color
    var isSystemDefault: Bool = false
    var isMulticolor: Bool = false
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

func customBadge(text: String) -> some View {
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
