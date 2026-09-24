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

// MARK: - Settings layout

private struct FeatureSettingsPage<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                content
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct FeatureSettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    var description: String? = nil
    let content: Content

    init(
        _ title: String,
        systemImage: String,
        description: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.effectiveAccent)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    if let description {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)

            Divider()
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
        }
    }
}

private struct FeatureSettingsRow<Control: View>: View {
    let title: String
    var detail: String? = nil
    let control: Control

    init(_ title: String, detail: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                label
                Spacer(minLength: 24)
                control
            }
            VStack(alignment: .leading, spacing: 10) {
                label
                control
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private extension View {
    func featureRowDivider() -> some View {
        overlay(alignment: .bottom) {
            Divider().padding(.leading, 16)
        }
    }
}

// MARK: - Calendar & Reminders

struct CalendarSettingsPage: View {
    @StateObject private var data = CalendarSettingsDataProvider()

    @Default(.hideCompletedReminders) var hideCompletedReminders
    @Default(.hideAllDayEvents) var hideAllDayEvents
    @Default(.autoScrollToNextEvent) var autoScrollToNextEvent
    @Default(.showFullEventTitles) var showFullEventTitles

    var body: some View {
        FeatureSettingsPage {
            FeatureSettingsCard("Display", systemImage: "calendar.badge.clock") {
                FeatureSettingsRow("Hide completed reminders") {
                    Defaults.Toggle("Hide completed reminders", key: .hideCompletedReminders).labelsHidden()
                }.featureRowDivider()
                FeatureSettingsRow("Hide all-day events") {
                    Defaults.Toggle("Hide all-day events", key: .hideAllDayEvents).labelsHidden()
                }.featureRowDivider()
                FeatureSettingsRow("Auto-scroll to next event") {
                    Defaults.Toggle("Auto-scroll to next event", key: .autoScrollToNextEvent).labelsHidden()
                }.featureRowDivider()
                FeatureSettingsRow("Always show full event titles") {
                    Defaults.Toggle("Always show full event titles", key: .showFullEventTitles).labelsHidden()
                }
            }

            FeatureSettingsCard("Calendars", systemImage: "calendar") {
                calendarListSection
            }
            FeatureSettingsCard("Reminders", systemImage: "checklist") {
                reminderListSection
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
        .padding(16)
    }

    @ViewBuilder
    private func listContent(_ calendars: [CalendarModel], emptyMessage: String) -> some View {
        if data.isLoading && calendars.isEmpty {
            ProgressView().controlSize(.small).padding(16)
        } else if calendars.isEmpty {
            Text(emptyMessage)
                .foregroundStyle(.secondary)
                .padding(16)
        } else {
            ForEach(calendars, id: \.id) { calendar in
                FeatureSettingsRow(calendar.title) {
                    Toggle(calendar.title, isOn: Binding(
                        get: { data.isSelected(calendar) },
                        set: { data.setSelected(calendar, isSelected: $0) }
                    ))
                    .labelsHidden()
                    .tint(lighterColor(from: calendar.color))
                }
                .featureRowDivider()
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
        FeatureSettingsPage {
            FeatureSettingsCard(
                "Shelf Behavior",
                systemImage: "tray.full",
                description: "Items remain on the Shelf when the extension is turned off."
            ) {
                FeatureSettingsRow("Open shelf by default", detail: "Opens automatically when items are present.") {
                    Defaults.Toggle("Open shelf by default", key: .openShelfByDefault).labelsHidden()
                }.featureRowDivider()
                FeatureSettingsRow("Expanded drag detection", detail: "Uses a larger drop target around the notch.") {
                    Defaults.Toggle("Expanded drag detection", key: .expandedDragDetection).labelsHidden()
                }
                .onChange(of: expandedDragDetection) {
                    NotificationCenter.default.post(
                        name: Notification.Name.expandedDragDetectionChanged,
                        object: nil
                    )
                }
                .featureRowDivider()
                FeatureSettingsRow("Copy items on drag") {
                    Defaults.Toggle("Copy items on drag", key: .copyOnDrag).labelsHidden()
                }.featureRowDivider()
                FeatureSettingsRow("Remove after dragging") {
                    Defaults.Toggle("Remove after dragging", key: .autoRemoveShelfItems).labelsHidden()
                }
            }

            FeatureSettingsCard(
                "Quick Share",
                systemImage: "square.and.arrow.up",
                description: "Choose the service used for files selected from or dropped onto the Shelf."
            ) {
                FeatureSettingsRow("Sharing service") {
                    Picker("Sharing service", selection: $quickShareProvider) {
                        ForEach(shareData.providersIncludingSelected(id: quickShareProvider), id: \.id) { provider in
                            providerLabel(provider)
                                .tag(provider.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(minWidth: 180)
                }
                .featureRowDivider()

                if let selectedProvider {
                    HStack(spacing: 10) {
                        providerIcon(selectedProvider)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedProvider.id).font(.subheadline.weight(.medium))
                            Text("Files dropped on the shelf will be shared via this service")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Current Quick Share service: \(selectedProvider.id)")
                }

                if shareData.isLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Discovering available services…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }.padding(16)
                } else if shareData.didLoad && shareData.providers.isEmpty {
                    Text("No sharing services were discovered.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(16)
                }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        FeatureSettingsPage {
            FeatureSettingsCard("Media Source", systemImage: "music.note") {
                FeatureSettingsRow("Music source") {
                    Picker("Music source", selection: $mediaController) {
                        ForEach(availableMediaControllers) { controller in
                            Text(controller.rawValue).tag(controller)
                        }
                    }
                    .labelsHidden()
                    .frame(minWidth: 180)
                }
                .onChange(of: mediaController) { _, _ in
                    NotificationCenter.default.post(
                        name: Notification.Name.mediaControllerChanged,
                        object: nil
                    )
                }.featureRowDivider()
                if MusicManager.shared.isNowPlayingDeprecated {
                    HStack(spacing: 4) {
                        Text("YouTube Music requires Pear Desktop.")
                        Link(
                            "Learn more",
                            destination: URL(string: "https://github.com/pear-devs/pear-desktop")!
                        )
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(16)
                } else {
                    Text("'Now Playing' was the only option on previous versions and works with all media apps.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .padding(16)
                }
            }

            FeatureSettingsCard("Playback", systemImage: "play.circle", description: "Control when and how media appears around the notch.") {
                FeatureSettingsRow("Show music live activity") {
                    Toggle("Show music live activity", isOn: reduceMotion
                        ? $coordinator.musicLiveActivityEnabled
                        : $coordinator.musicLiveActivityEnabled.animation())
                        .labelsHidden()
                }.featureRowDivider()
                FeatureSettingsRow("Show sneak peek", detail: "Appears when playback changes.") {
                    Toggle("Show sneak peek", isOn: $enableSneakPeek).labelsHidden()
                }.featureRowDivider()
                FeatureSettingsRow("Sneak Peek style") {
                    Picker("Sneak Peek style", selection: $sneakPeekStyles) {
                        ForEach(SneakPeekStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .labelsHidden()
                    .frame(minWidth: 150)
                }
                .featureRowDivider()
                FeatureSettingsRow("Inactivity timeout", detail: waitIntervalDescription) {
                    Stepper("Inactivity timeout", value: $waitInterval, in: 0...10, step: 1)
                        .labelsHidden()
                        .accessibilityValue(waitIntervalDescription)
                }.featureRowDivider()
                FeatureSettingsRow("Full screen behavior") {
                    HStack(spacing: 8) {
                        customBadge(text: "Beta")
                        Picker("Full screen behavior", selection: $hideNotchOption) {
                            Text("Hide for all apps").tag(HideNotchOption.always)
                            Text("Hide for media app only").tag(HideNotchOption.nowPlayingOnly)
                            Text("Never hide").tag(HideNotchOption.never)
                        }
                        .labelsHidden()
                    }
                }
            }

            FeatureSettingsCard("Appearance", systemImage: "paintpalette") {
                FeatureSettingsRow("Colored spectrogram") {
                    Defaults.Toggle("Colored spectrogram", key: .coloredSpectrogram).labelsHidden()
                }.featureRowDivider()
                FeatureSettingsRow("Player tinting") {
                    Defaults.Toggle("Player tinting", key: .playerColorTinting).labelsHidden()
                }.featureRowDivider()
                FeatureSettingsRow("Album art blur") {
                    Defaults.Toggle("Album art blur", key: .lightingEffect).labelsHidden()
                }.featureRowDivider()
                FeatureSettingsRow("Slider color") {
                    Picker("Slider color", selection: $sliderColor) {
                        ForEach(SliderColorEnum.allCases, id: \.self) { option in
                            Text(option.rawValue)
                        }
                    }
                    .labelsHidden()
                }
            }

            FeatureSettingsCard("Media Controls", systemImage: "slider.horizontal.3", description: "Choose and arrange the five controls shown in the player. Volume expands when active.") {
                MusicSlotConfigurationView()
                Divider()
                FeatureSettingsRow("Show lyrics below artist name") {
                    HStack(spacing: 8) {
                        customBadge(text: "Beta")
                        Defaults.Toggle("Show lyrics below artist name", key: .enableLyrics).labelsHidden()
                    }
                }
            }

            visualizerSection

            FeatureSettingsCard("Keyboard", systemImage: "keyboard", description: "Configure the media shortcut in the central Shortcuts page.") {
                Button {
                    openShortcuts(.media)
                } label: {
                    HStack {
                        Text("Open Keyboard Shortcuts")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .padding(16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the Shortcuts settings page focused on Media")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Media")
    }

    @ViewBuilder
    private var visualizerSection: some View {
        FeatureSettingsCard(
            "Live Activity Animation",
            systemImage: "waveform",
            description: "Custom music live activity animations are coming soon."
        ) {
            FeatureSettingsRow("Use music visualizer spectrogram") {
                HStack(spacing: 8) {
                    customBadge(text: "Coming soon")
                    Toggle("Use music visualizer spectrogram", isOn: reduceMotion
                        ? $useMusicVisualizer
                        : $useMusicVisualizer.animation())
                        .labelsHidden()
                        .disabled(true)
                }
            }
            .featureRowDivider()
            if !useMusicVisualizer {
                if customVisualizers.count > 0 {
                    FeatureSettingsRow("Selected animation") {
                        Picker("Selected animation", selection: $selectedVisualizer) {
                            ForEach(customVisualizers, id: \.self) { visualizer in
                                Text(visualizer.name).tag(visualizer)
                            }
                        }
                        .labelsHidden()
                    }
                } else {
                    FeatureSettingsRow("Selected animation") {
                        Text("No custom animation available")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        FeatureSettingsCard("Custom Visualizers", systemImage: "sparkles", description: "Add Lottie animations from a JSON URL.") {
            List {
                ForEach(customVisualizers, id: \.self) { visualizer in
                    Button {
                        selectedListVisualizer = selectedListVisualizer == visualizer ? nil : visualizer
                    } label: {
                        HStack {
                            LottieView(url: visualizer.url, speed: visualizer.speed, loopMode: .loop)
                                .frame(width: 30, height: 30, alignment: .center)
                                .accessibilityHidden(true)
                            Text(visualizer.name)
                            Spacer(minLength: 0)
                            if selectedVisualizer == visualizer {
                                Text("Selected")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.trailing, 8)
                            }
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(
                        selectedListVisualizer != nil
                            ? selectedListVisualizer == visualizer
                                ? Color.effectiveAccent.opacity(0.22) : Color.clear : Color.clear,
                        in: RoundedRectangle(cornerRadius: 5)
                    )
                    .accessibilityLabel(visualizer.name)
                    .accessibilityValue(selectedVisualizer == visualizer ? "Current animation" : "")
                    .accessibilityAddTraits(selectedListVisualizer == visualizer ? .isSelected : [])
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
                    .accessibilityLabel("Add visualizer")
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
                    .disabled(selectedListVisualizer == nil)
                    .accessibilityLabel("Remove selected visualizer")
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
                VStack(alignment: .leading, spacing: 20) {
                    Label("Add Visualizer", systemImage: "waveform.badge.plus")
                        .font(.title2.bold())
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                        GridRow {
                            Text("Name")
                            TextField("Visualizer name", text: $name)
                        }
                        GridRow {
                            Text("Lottie JSON URL")
                            TextField("https://example.com/animation.json", text: $url)
                        }
                        GridRow {
                            Text("Speed")
                            HStack {
                                Slider(value: $speed, in: 0...2, step: 0.1)
                                Text("\(speed, specifier: "%.1f")x")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 38, alignment: .trailing)
                            }
                        }
                    }
                    Divider()
                    HStack {
                        Spacer()
                        Button {
                            isPresented.toggle()
                        } label: {
                            Text("Cancel")
                        }
                        .keyboardShortcut(.cancelAction)
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
                            Text("Add")
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .padding(24)
                .frame(width: 520)
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

    private var waitIntervalDescription: String {
        String(format: "%.0f seconds", Defaults[.waitInterval])
    }
}

// MARK: - HUD

struct HUDSettingsPage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Default(.inlineHUD) var inlineHUD
    @Default(.enableGradient) var enableGradient
    @Default(.optionKeyAction) var optionKeyAction
    @StateObject private var status = HUDStatusProvider()

    private var inputAccessPresentation: HUDInputAccessPresentation {
        HUDInputAccessPresentation(hasInputAccess: status.hasInputAccess)
    }

    var body: some View {
        FeatureSettingsPage {
            FeatureSettingsCard(
                "System Access",
                systemImage: "hand.raised",
                description: "The HUD needs Accessibility access to replace the standard macOS volume and brightness indicators."
            ) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        accessStatus
                        Spacer(minLength: 16)
                        accessActions
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        accessStatus
                        accessActions
                    }
                }
                .padding(16)
            }

            FeatureSettingsCard("Behavior", systemImage: "switch.2") {
                FeatureSettingsRow("Option key behavior") {
                    Picker("Option key behavior", selection: $optionKeyAction) {
                        ForEach(OptionKeyAction.allCases) { opt in
                            Text(opt.rawValue).tag(opt)
                        }
                    }
                    .labelsHidden()
                }.featureRowDivider()
                FeatureSettingsRow("Progress bar style") {
                    Picker("Progress bar style", selection: $enableGradient) {
                        Text("Hierarchical").tag(false)
                        Text("Gradient").tag(true)
                    }
                    .labelsHidden()
                }.featureRowDivider()
                FeatureSettingsRow("Glowing effect") {
                    Defaults.Toggle("Glowing effect", key: .systemEventIndicatorShadow).labelsHidden()
                }.featureRowDivider()
                FeatureSettingsRow("Use accent color") {
                    Defaults.Toggle("Use accent color", key: .systemEventIndicatorUseAccent).labelsHidden()
                }
            }

            FeatureSettingsCard("Open Notch", systemImage: "rectangle.topthird.inset.filled") {
                FeatureSettingsRow("Show HUD in open notch") {
                    customBadge(text: "Beta")
                    Defaults.Toggle("Show HUD in open notch", key: .showOpenNotchHUD).labelsHidden()
                }.featureRowDivider()
                FeatureSettingsRow("Show percentage") {
                    Defaults.Toggle("Show percentage", key: .showOpenNotchHUDPercentage).labelsHidden()
                }
                .disabled(!Defaults[.showOpenNotchHUD])
            }

            FeatureSettingsCard("Closed Notch", systemImage: "rectangle.topthird.inset") {
                FeatureSettingsRow("HUD style") {
                    Picker("HUD style", selection: $inlineHUD) {
                        Text("Default").tag(false)
                        Text("Inline").tag(true)
                    }
                    .labelsHidden()
                }
                .onChange(of: Defaults[.inlineHUD]) {
                    if Defaults[.inlineHUD] {
                        withAnimation(reduceMotion ? nil : .default) {
                            Defaults[.systemEventIndicatorShadow] = false
                            Defaults[.enableGradient] = false
                        }
                    }
                }
                .featureRowDivider()
                FeatureSettingsRow("Show percentage") {
                    Defaults.Toggle("Show percentage", key: .showClosedNotchHUDPercentage).labelsHidden()
                }
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

    private var accessStatus: some View {
        Label(inputAccessPresentation.message, systemImage: inputAccessPresentation.symbolName)
            .font(.subheadline)
            .foregroundStyle(status.hasInputAccess ? Color.green : Color.secondary)
            .accessibilityLabel("Accessibility status: \(inputAccessPresentation.message)")
    }

    private var accessActions: some View {
        HStack(spacing: 8) {
            if inputAccessPresentation.showsRequestButton {
                Button("Request Accessibility") {
                    NotchKitRuntime.shared.requestHUDInputAccess()
                }
                .buttonStyle(.borderedProminent)
            }
            Button("Refresh Status") {
                Task {
                    await status.refresh()
                    NotchKitRuntime.shared.reconcilePermissionGatedFeatures()
                }
            }
        }
    }
}

// MARK: - Camera Mirror

struct CameraMirrorSettingsPage: View {
    @Default(.mirrorShape) var mirrorShape

    var body: some View {
        FeatureSettingsPage {
            FeatureSettingsCard(
                "Camera Mirror",
                systemImage: "web.camera",
                description: "Camera access is requested only when the mirror is opened, never while configuring it here."
            ) {
                FeatureSettingsRow("Mirror shape") {
                    Picker("Mirror shape", selection: $mirrorShape) {
                        Text("Circle").tag(MirrorShapeEnum.circle)
                        Text("Square").tag(MirrorShapeEnum.rectangle)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                if !isCameraInputAvailable() {
                    Divider()
                    Label("No camera input was detected on this Mac.", systemImage: "web.camera.fill.badge.exclamationmark")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(16)
                }
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
