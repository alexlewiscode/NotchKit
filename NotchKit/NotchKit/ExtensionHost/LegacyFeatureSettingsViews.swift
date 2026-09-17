//
//  LegacyFeatureSettingsViews.swift
//  NotchKit
//
//  Configuration pages for Calendar & Reminders, Shelf, Media, HUD, and Camera
//  Mirror. These features are not extracted in this milestone; the pages are
//  host-owned configuration surfaces served through the settings catalog.
//
//  Rendering a page must not construct an extension, call `activate()`, start a
//  long-lived feature service, or request a permission automatically.
//

import AVFoundation
import Defaults
import EventKit
import NotchExtensionRuntime
import SwiftUI

// MARK: - Calendar & Reminders

struct CalendarSettingsPage: View {
    @StateObject private var data = CalendarSettingsDataProvider()

    @Default(.hideCompletedReminders) var hideCompletedReminders
    @Default(.hideAllDayEvents) var hideAllDayEvents
    @Default(.autoScrollToNextEvent) var autoScrollToNextEvent
    @Default(.showFullEventTitles) var showFullEventTitles

    var body: some View {
        Form {
            Defaults.Toggle(key: .hideCompletedReminders) {
                Text("Hide completed reminders")
            }
            Defaults.Toggle(key: .hideAllDayEvents) {
                Text("Hide all-day events")
            }
            Defaults.Toggle(key: .autoScrollToNextEvent) {
                Text("Auto-scroll to next event")
            }
            Defaults.Toggle(key: .showFullEventTitles) {
                Text("Always show full event titles")
            }

            Section {
                calendarListSection
            } header: {
                Text("Calendars")
            }

            Section {
                reminderListSection
            } header: {
                Text("Reminders")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Calendar & Reminders")
        .task {
            data.refreshStatuses()
            await data.loadLists()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await data.refreshAfterReturningToApp() }
        }
    }

    @ViewBuilder
    private var calendarListSection: some View {
        if data.eventAuthorization != .fullAccess {
            accessSection(
                message: "Calendar access is not granted. Enable it in System Settings.",
                grantTitle: "Grant Calendar Access",
                settingsPath: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars",
                request: { await data.requestEventAccess() }
            )
        } else {
            listContent(data.eventCalendars, emptyMessage: "No calendars available")
        }
    }

    @ViewBuilder
    private var reminderListSection: some View {
        if data.reminderAuthorization != .fullAccess {
            accessSection(
                message: "Reminder access is not granted. Enable it in System Settings.",
                grantTitle: "Grant Reminder Access",
                settingsPath: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders",
                request: { await data.requestReminderAccess() }
            )
        } else {
            listContent(data.reminderLists, emptyMessage: "No reminder lists available")
        }
    }

    @ViewBuilder
    private func accessSection(
        message: String,
        grantTitle: String,
        settingsPath: String,
        request: @escaping () async -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button(grantTitle) {
                    Task { await request() }
                }
                .buttonStyle(.borderedProminent)
                Button("Open System Settings") {
                    if let url = URL(string: settingsPath) {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func listContent(_ calendars: [CalendarModel], emptyMessage: String) -> some View {
        if data.isLoading && calendars.isEmpty {
            ProgressView().controlSize(.small)
        } else if calendars.isEmpty {
            Text(emptyMessage)
                .foregroundStyle(.secondary)
        } else {
            ForEach(calendars, id: \.id) { calendar in
                Toggle(
                    isOn: Binding(
                        get: { data.isSelected(calendar) },
                        set: { data.setSelected(calendar, isSelected: $0) }
                    )
                ) {
                    Text(calendar.title)
                }
                .accentColor(lighterColor(from: calendar.color))
            }
        }
    }
}

// MARK: - Shelf

struct ShelfSettingsPage: View {
    @Default(.quickShareProvider) private var quickShareProvider
    @Default(.expandedDragDetection) private var expandedDragDetection: Bool
    @StateObject private var shareData = ShelfShareProviderDataSource()

    private var selectedProvider: QuickShareProvider? {
        shareData.selectedProvider(id: quickShareProvider)
            ?? shareData.providersIncludingSelected(id: quickShareProvider)
                .first { $0.id == quickShareProvider }
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .openShelfByDefault) {
                    Text("Open shelf by default if items are present")
                }
                Defaults.Toggle(key: .expandedDragDetection) {
                    Text("Expanded drag detection area")
                }
                .onChange(of: expandedDragDetection) {
                    NotificationCenter.default.post(
                        name: Notification.Name.expandedDragDetectionChanged,
                        object: nil
                    )
                }
                Defaults.Toggle(key: .copyOnDrag) {
                    Text("Copy items on drag")
                }
                Defaults.Toggle(key: .autoRemoveShelfItems) {
                    Text("Remove from shelf after dragging")
                }
            } header: {
                Text("General")
            } footer: {
                Text("Use the switch on the Extensions page to turn the Shelf on or off. Items already on the Shelf are kept while it is off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Quick Share Service", selection: $quickShareProvider) {
                    ForEach(shareData.providersIncludingSelected(id: quickShareProvider), id: \.id) { provider in
                        providerLabel(provider)
                            .tag(provider.id)
                    }
                }
                .pickerStyle(.menu)

                if let selectedProvider {
                    HStack {
                        providerIcon(selectedProvider)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Currently selected: \(selectedProvider.id)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Files dropped on the shelf will be shared via this service")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if shareData.isLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Discovering available services…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if shareData.didLoad && shareData.providers.isEmpty {
                    Text("No sharing services were discovered.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Quick Share")
            } footer: {
                Text("Choose which service to use when sharing files from the shelf. Click the shelf button to select files, or drag files onto it to share immediately.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Shelf")
        .task {
            shareData.load()
        }
        .onDisappear {
            shareData.cancel()
        }
    }

    @ViewBuilder
    private func providerLabel(_ provider: QuickShareProvider) -> some View {
        HStack {
            providerIcon(provider)
            Text(provider.id)
        }
    }

    @ViewBuilder
    private func providerIcon(_ provider: QuickShareProvider) -> some View {
        Group {
            if let imageData = provider.imageData, let image = NSImage(data: imageData) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .frame(width: 16, height: 16)
        .foregroundColor(.accentColor)
    }
}

// MARK: - Media

struct MediaSettingsPage: View {
    @Environment(\.openShortcuts) private var openShortcuts

    @Default(.waitInterval) var waitInterval
    @Default(.mediaController) var mediaController
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.hideNotchOption) var hideNotchOption
    @Default(.enableSneakPeek) private var enableSneakPeek
    @Default(.sneakPeekStyles) var sneakPeekStyles
    @Default(.coloredSpectrogram) var coloredSpectrogram
    @Default(.playerColorTinting) var playerColorTinting
    @Default(.lightingEffect) var lightingEffect
    @Default(.sliderColor) var sliderColor
    @Default(.useMusicVisualizer) var useMusicVisualizer
    @Default(.customVisualizers) var customVisualizers
    @Default(.selectedVisualizer) var selectedVisualizer

    @State private var selectedListVisualizer: CustomVisualizer? = nil
    @State private var isPresented: Bool = false
    @State private var name: String = ""
    @State private var url: String = ""
    @State private var speed: CGFloat = 1.0

    var body: some View {
        Form {
            Section {
                Picker("Music Source", selection: $mediaController) {
                    ForEach(availableMediaControllers) { controller in
                        Text(controller.rawValue).tag(controller)
                    }
                }
                .onChange(of: mediaController) { _, _ in
                    NotificationCenter.default.post(
                        name: Notification.Name.mediaControllerChanged,
                        object: nil
                    )
                }
            } header: {
                Text("Media Source")
            } footer: {
                if MusicManager.shared.isNowPlayingDeprecated {
                    HStack {
                        Text("YouTube Music requires this third-party app to be installed: ")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Link(
                            "https://github.com/pear-devs/pear-desktop",
                            destination: URL(string: "https://github.com/pear-devs/pear-desktop")!
                        )
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                } else {
                    Text("'Now Playing' was the only option on previous versions and works with all media apps.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            Section {
                Toggle(
                    "Show music live activity",
                    isOn: $coordinator.musicLiveActivityEnabled.animation()
                )
                Toggle("Show sneak peek on playback changes", isOn: $enableSneakPeek)
                Picker("Sneak Peek Style", selection: $sneakPeekStyles) {
                    ForEach(SneakPeekStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                Stepper(value: $waitInterval, in: 0...10, step: 1) {
                    HStack {
                        Text("Media inactivity timeout")
                        Spacer()
                        Text("\(Defaults[.waitInterval], specifier: "%.0f") seconds")
                            .foregroundStyle(.secondary)
                    }
                }
                Picker(
                    selection: $hideNotchOption,
                    label:
                        HStack {
                            Text("Full screen behavior")
                            customBadge(text: "Beta")
                        }
                ) {
                    Text("Hide for all apps").tag(HideNotchOption.always)
                    Text("Hide for media app only").tag(HideNotchOption.nowPlayingOnly)
                    Text("Never hide").tag(HideNotchOption.never)
                }
            } header: {
                Text("Media playback live activity")
            }

            Section {
                Defaults.Toggle(key: .coloredSpectrogram) {
                    Text("Colored spectrogram")
                }
                Defaults.Toggle("Player tinting", key: .playerColorTinting)
                Defaults.Toggle(key: .lightingEffect) {
                    Text("Enable blur effect behind album art")
                }
                Picker("Slider color", selection: $sliderColor) {
                    ForEach(SliderColorEnum.allCases, id: \.self) { option in
                        Text(option.rawValue)
                    }
                }
            } header: {
                Text("Appearance")
            }

            Section {
                MusicSlotConfigurationView()
                Defaults.Toggle(key: .enableLyrics) {
                    HStack {
                        Text("Show lyrics below artist name")
                        customBadge(text: "Beta")
                    }
                }
            } header: {
                Text("Media controls")
            } footer: {
                Text("Customize which controls appear in the music player. Volume expands when active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            visualizerSection

            Section {
                Button {
                    openShortcuts(.media)
                } label: {
                    Label("Keyboard Shortcuts", systemImage: "keyboard")
                }
            } footer: {
                Text("Configure the media shortcut in the central Shortcuts page.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Media")
    }

    @ViewBuilder
    private var visualizerSection: some View {
        Section {
            Toggle("Use music visualizer spectrogram", isOn: $useMusicVisualizer.animation())
                .disabled(true)
            if !useMusicVisualizer {
                if customVisualizers.count > 0 {
                    Picker("Selected animation", selection: $selectedVisualizer) {
                        ForEach(customVisualizers, id: \.self) { visualizer in
                            Text(visualizer.name).tag(visualizer)
                        }
                    }
                } else {
                    HStack {
                        Text("Selected animation")
                        Spacer()
                        Text("No custom animation available")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            HStack {
                Text("Custom music live activity animation")
                customBadge(text: "Coming soon")
            }
        }

        Section {
            List {
                ForEach(customVisualizers, id: \.self) { visualizer in
                    HStack {
                        LottieView(url: visualizer.url, speed: visualizer.speed, loopMode: .loop)
                            .frame(width: 30, height: 30, alignment: .center)
                        Text(visualizer.name)
                        Spacer(minLength: 0)
                        if selectedVisualizer == visualizer {
                            Text("selected")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                                .padding(.trailing, 8)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.vertical, 2)
                    .background(
                        selectedListVisualizer != nil
                            ? selectedListVisualizer == visualizer
                                ? Color.effectiveAccent : Color.clear : Color.clear,
                        in: RoundedRectangle(cornerRadius: 5)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedListVisualizer == visualizer {
                            selectedListVisualizer = nil
                            return
                        }
                        selectedListVisualizer = visualizer
                    }
                }
            }
            .safeAreaPadding(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
            .frame(minHeight: 120)
            .actionBar {
                HStack(spacing: 5) {
                    Button {
                        name = ""
                        url = ""
                        speed = 1.0
                        isPresented.toggle()
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(.secondary)
                            .contentShape(Rectangle())
                    }
                    Divider()
                    Button {
                        if let visualizer = selectedListVisualizer {
                            selectedListVisualizer = nil
                            customVisualizers.remove(at: customVisualizers.firstIndex(of: visualizer)!)
                            if visualizer == selectedVisualizer && customVisualizers.count > 0 {
                                selectedVisualizer = customVisualizers[0]
                            }
                        }
                    } label: {
                        Image(systemName: "minus")
                            .foregroundStyle(.secondary)
                            .contentShape(Rectangle())
                    }
                }
            }
            .controlSize(.small)
            .buttonStyle(PlainButtonStyle())
            .overlay {
                if customVisualizers.isEmpty {
                    Text("No custom visualizer")
                        .foregroundStyle(Color(.secondaryLabelColor))
                        .padding(.bottom, 22)
                }
            }
            .sheet(isPresented: $isPresented) {
                VStack(alignment: .leading) {
                    Text("Add new visualizer")
                        .font(.largeTitle.bold())
                        .padding(.vertical)
                    TextField("Name", text: $name)
                    TextField("Lottie JSON URL", text: $url)
                    HStack {
                        Text("Speed")
                        Spacer(minLength: 80)
                        Text("\(speed, specifier: "%.1f")s")
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                        Slider(value: $speed, in: 0...2, step: 0.1)
                    }
                    .padding(.vertical)
                    HStack {
                        Button {
                            isPresented.toggle()
                        } label: {
                            Text("Cancel").frame(maxWidth: .infinity, alignment: .center)
                        }
                        Button {
                            if let parsedURL = URL(string: url) {
                                let visualizer = CustomVisualizer(
                                    UUID: UUID(),
                                    name: name,
                                    url: parsedURL,
                                    speed: speed
                                )
                                if !customVisualizers.contains(visualizer) {
                                    customVisualizers.append(visualizer)
                                }
                            }
                            isPresented.toggle()
                        } label: {
                            Text("Add").frame(maxWidth: .infinity, alignment: .center)
                        }
                        .buttonStyle(BorderedProminentButtonStyle())
                    }
                }
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .controlSize(.extraLarge)
                .padding()
            }
        } header: {
            HStack(spacing: 0) {
                Text("Custom vizualizers (Lottie)")
                if !Defaults[.customVisualizers].isEmpty {
                    Text(" – \(Defaults[.customVisualizers].count)")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var availableMediaControllers: [MediaControllerType] {
        if MusicManager.shared.isNowPlayingDeprecated {
            return MediaControllerType.allCases.filter { $0 != .nowPlaying }
        } else {
            return MediaControllerType.allCases
        }
    }
}

// MARK: - HUD

struct HUDSettingsPage: View {
    @Default(.inlineHUD) var inlineHUD
    @Default(.enableGradient) var enableGradient
    @Default(.optionKeyAction) var optionKeyAction
    @StateObject private var status = HUDStatusProvider()

    private var inputAccessPresentation: HUDInputAccessPresentation {
        HUDInputAccessPresentation(hasInputAccess: status.hasInputAccess)
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Replace system HUD")
                        .font(.headline)
                    Text("Replaces the standard macOS volume, display brightness, and keyboard brightness HUDs with a custom design. Use the switch on the Extensions page to turn the HUD on or off.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 12) {
                    Image(systemName: inputAccessPresentation.symbolName)
                        .foregroundStyle(status.hasInputAccess ? Color.green : Color.secondary)
                    Text(inputAccessPresentation.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if inputAccessPresentation.showsRequestButton {
                        Button("Request Accessibility") {
                            NotchKitRuntime.shared.requestHUDInputAccess()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button("Refresh Status") {
                        Task {
                            await status.refresh()
                            // Re-drive the runtime from the same app-side source
                            // so a granted, still-enabled HUD can activate
                            // without a second click.
                            NotchKitRuntime.shared.reconcilePermissionGatedFeatures()
                        }
                    }
                }
                .padding(.top, 6)
            }

            Section {
                Picker("Option key behaviour", selection: $optionKeyAction) {
                    ForEach(OptionKeyAction.allCases) { opt in
                        Text(opt.rawValue).tag(opt)
                    }
                }
                Picker("Progress bar style", selection: $enableGradient) {
                    Text("Hierarchical").tag(false)
                    Text("Gradient").tag(true)
                }
                Defaults.Toggle(key: .systemEventIndicatorShadow) {
                    Text("Enable glowing effect")
                }
                Defaults.Toggle(key: .systemEventIndicatorUseAccent) {
                    Text("Tint progress bar with accent color")
                }
            } header: {
                Text("General")
            }

            Section {
                Defaults.Toggle(key: .showOpenNotchHUD) {
                    Text("Show HUD in open notch")
                }
                Defaults.Toggle(key: .showOpenNotchHUDPercentage) {
                    Text("Show percentage")
                }
                .disabled(!Defaults[.showOpenNotchHUD])
            } header: {
                HStack {
                    Text("Open Notch")
                    customBadge(text: "Beta")
                }
            }

            Section {
                Picker("HUD style", selection: $inlineHUD) {
                    Text("Default").tag(false)
                    Text("Inline").tag(true)
                }
                .onChange(of: Defaults[.inlineHUD]) {
                    if Defaults[.inlineHUD] {
                        withAnimation {
                            Defaults[.systemEventIndicatorShadow] = false
                            Defaults[.enableGradient] = false
                        }
                    }
                }
                Defaults.Toggle(key: .showClosedNotchHUDPercentage) {
                    Text("Show percentage")
                }
            } header: {
                Text("Closed Notch")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("HUD")
        .task {
            await status.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Read-only refresh when returning from System Settings. Does not
            // prompt, start the interceptor, or poll; reconciliation only
            // retries features already waiting on a now-granted permission.
            Task {
                await status.refresh()
                NotchKitRuntime.shared.reconcilePermissionGatedFeatures()
            }
        }
    }
}

// MARK: - Camera Mirror

struct CameraMirrorSettingsPage: View {
    @Default(.mirrorShape) var mirrorShape

    var body: some View {
        Form {
            Section {
                Picker("Mirror shape", selection: $mirrorShape) {
                    Text("Circle").tag(MirrorShapeEnum.circle)
                    Text("Square").tag(MirrorShapeEnum.rectangle)
                }
                if !isCameraInputAvailable() {
                    Text("No camera input was detected on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Camera Mirror")
            } footer: {
                Text("Use the switch on the Extensions page to turn the Camera Mirror on or off. Camera access is requested the first time the mirror is opened, not while configuring it here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Camera Mirror")
    }
}

/// Device presence only; never requests camera permission.
func isCameraInputAvailable() -> Bool {
    AVCaptureDevice.default(for: .video) != nil
}
