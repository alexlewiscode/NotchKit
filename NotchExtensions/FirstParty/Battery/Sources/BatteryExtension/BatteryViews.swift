//
//  BatteryViews.swift
//  BatteryExtension
//
//  Battery UI, moved out of the host app. Views are self-contained: they read
//  geometry from the SDK environment and settings from `BatterySettings`, and
//  never import app internals.
//

import NotchExtensionSDK
import SwiftUI

/// A battery glyph with charge level and a charging/plugged indicator.
public struct BatteryView: View {
    public var levelBattery: Float
    public var isPluggedIn: Bool
    public var isCharging: Bool
    public var isInLowPowerMode: Bool
    public var batteryWidth: CGFloat
    public var isForNotification: Bool
    public var icon: String

    public init(
        levelBattery: Float,
        isPluggedIn: Bool,
        isCharging: Bool,
        isInLowPowerMode: Bool,
        batteryWidth: CGFloat = 26,
        isForNotification: Bool,
        icon: String = "battery.0"
    ) {
        self.levelBattery = levelBattery
        self.isPluggedIn = isPluggedIn
        self.isCharging = isCharging
        self.isInLowPowerMode = isInLowPowerMode
        self.batteryWidth = batteryWidth
        self.isForNotification = isForNotification
        self.icon = icon
    }

    private var iconStatus: String {
        if isCharging { return "bolt" }
        if isPluggedIn { return "plug" }
        return ""
    }

    private var batteryColor: Color {
        if isInLowPowerMode {
            return .yellow
        } else if levelBattery <= 20 && !isCharging && !isPluggedIn {
            return .red
        } else if isCharging || isPluggedIn || levelBattery == 100 {
            return .green
        } else {
            return .white
        }
    }

    public var body: some View {
        ZStack(alignment: .leading) {
            Image(systemName: icon)
                .resizable()
                .fontWeight(.thin)
                .aspectRatio(contentMode: .fit)
                .foregroundColor(.white.opacity(0.5))
                .frame(width: batteryWidth + 1)

            RoundedRectangle(cornerRadius: 2.5)
                .fill(batteryColor)
                .frame(
                    width: CGFloat(((CGFloat(CFloat(levelBattery)) / 100) * (batteryWidth - 6))),
                    height: (batteryWidth - 2.75) - 18
                )
                .padding(.leading, 2)

            if iconStatus != "" && (isForNotification || BatterySettings.showPowerStatusIcons) {
                Image(iconStatus)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(.white)
                    .frame(width: 17, height: 17)
                    .frame(width: batteryWidth, height: batteryWidth)
            }
        }
    }
}

/// The press feedback used by the battery button.
public struct ScaleButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

/// Detailed battery information popover.
public struct BatteryMenuView: View {
    public var isPluggedIn: Bool
    public var isCharging: Bool
    public var levelBattery: Float
    public var maxCapacity: Float
    public var timeToFullCharge: Int
    public var isInLowPowerMode: Bool
    public var onDismiss: () -> Void

    @Environment(\.openURL) private var openURL

    public init(
        isPluggedIn: Bool,
        isCharging: Bool,
        levelBattery: Float,
        maxCapacity: Float,
        timeToFullCharge: Int,
        isInLowPowerMode: Bool,
        onDismiss: @escaping () -> Void
    ) {
        self.isPluggedIn = isPluggedIn
        self.isCharging = isCharging
        self.levelBattery = levelBattery
        self.maxCapacity = maxCapacity
        self.timeToFullCharge = timeToFullCharge
        self.isInLowPowerMode = isInLowPowerMode
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Battery Status")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(Int(levelBattery))%")
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Max Capacity: \(Int(maxCapacity))%")
                    .font(.subheadline)
                if isInLowPowerMode {
                    Label("Low Power Mode", systemImage: "bolt.circle").font(.subheadline)
                }
                if isCharging {
                    Label("Charging", systemImage: "bolt.fill").font(.subheadline)
                }
                if isPluggedIn {
                    Label("Plugged In", systemImage: "powerplug.fill").font(.subheadline)
                }
                if timeToFullCharge > 0 {
                    Label("Time to Full Charge: \(timeToFullCharge) min", systemImage: "clock")
                        .font(.subheadline)
                }
                if !isCharging && isPluggedIn && levelBattery >= 80 {
                    Label("Charging on Hold: Desktop Mode", systemImage: "desktopcomputer")
                        .font(.subheadline)
                }
            }
            .padding(.vertical, 8)

            Divider().background(Color.white)

            Button(action: openBatteryPreferences) {
                Label("Battery Settings", systemImage: "gearshape").fontWeight(.regular)
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.plain)
            .padding(.vertical, 8)
        }
        .padding()
        .frame(width: 280)
        .foregroundColor(.white)
    }

    private func openBatteryPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.battery") {
            openURL(url)
            onDismiss()
        }
    }
}

/// The interactive battery button used in the open-notch header and the closed
/// notification. Popover state is owned by the caller, so the view has no host
/// dependency.
public struct BoringBatteryView: View {
    @State private var batteryWidth: CGFloat
    public var isCharging: Bool
    public var isInLowPowerMode: Bool
    public var isPluggedIn: Bool
    public var levelBattery: Float
    public var maxCapacity: Float
    public var timeToFullCharge: Int
    @State private var isForNotification: Bool
    @Binding private var isPopoverActive: Bool

    @State private var showPopupMenu: Bool = false
    @State private var isHoveringButton: Bool = false
    @State private var isHoveringPopover: Bool = false
    @State private var hideTask: Task<Void, Never>?

    public init(
        batteryWidth: CGFloat = 26,
        isCharging: Bool = false,
        isInLowPowerMode: Bool = false,
        isPluggedIn: Bool = false,
        levelBattery: Float = 0,
        maxCapacity: Float = 0,
        timeToFullCharge: Int = 0,
        isForNotification: Bool = false,
        isPopoverActive: Binding<Bool> = .constant(false)
    ) {
        _batteryWidth = State(initialValue: batteryWidth)
        self.isCharging = isCharging
        self.isInLowPowerMode = isInLowPowerMode
        self.isPluggedIn = isPluggedIn
        self.levelBattery = levelBattery
        self.maxCapacity = maxCapacity
        self.timeToFullCharge = timeToFullCharge
        _isForNotification = State(initialValue: isForNotification)
        _isPopoverActive = isPopoverActive
    }

    public var body: some View {
        Button(action: {
            withAnimation { showPopupMenu.toggle() }
        }) {
            HStack {
                if BatterySettings.showBatteryPercentage {
                    Text("\(Int32(levelBattery))%")
                        .font(.callout)
                        .foregroundStyle(.white)
                }
                BatteryView(
                    levelBattery: levelBattery,
                    isPluggedIn: isPluggedIn,
                    isCharging: isCharging,
                    isInLowPowerMode: isInLowPowerMode,
                    batteryWidth: batteryWidth,
                    isForNotification: isForNotification
                )
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .popover(isPresented: $showPopupMenu, arrowEdge: .bottom) {
            BatteryMenuView(
                isPluggedIn: isPluggedIn,
                isCharging: isCharging,
                levelBattery: levelBattery,
                maxCapacity: maxCapacity,
                timeToFullCharge: timeToFullCharge,
                isInLowPowerMode: isInLowPowerMode,
                onDismiss: { showPopupMenu = false }
            )
            .onHover { hovering in
                isHoveringPopover = hovering
                if hovering {
                    hideTask?.cancel()
                    hideTask = nil
                } else {
                    scheduleHideIfNeeded()
                }
            }
        }
        .onChange(of: showPopupMenu) { _, newValue in
            isPopoverActive = newValue
        }
        .onDisappear {
            hideTask?.cancel()
            hideTask = nil
        }
    }

    private func scheduleHideIfNeeded() {
        if isHoveringButton || isHoveringPopover { return }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await MainActor.run { withAnimation { showPopupMenu = false } }
        }
    }
}

/// The closed-notch battery notification. Reads core-owned geometry from the
/// SDK environment so it renders correctly per display.
public struct BatteryNotificationView: View {
    @ObservedObject private var monitor: BatteryMonitor
    @Environment(\.notchGeometry) private var geometry

    public init(monitor: BatteryMonitor) {
        self.monitor = monitor
    }

    public var body: some View {
        let snapshot = monitor.snapshot
        HStack(spacing: 0) {
            HStack {
                Text(statusText(snapshot))
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }

            Rectangle()
                .fill(.black)
                .frame(width: geometry.closedNotchWidth + 10)

            HStack {
                BoringBatteryView(
                    batteryWidth: 30,
                    isCharging: snapshot.isCharging,
                    isInLowPowerMode: snapshot.isInLowPowerMode,
                    isPluggedIn: snapshot.isPluggedIn,
                    levelBattery: snapshot.currentCapacity,
                    isForNotification: true
                )
            }
            .frame(width: 76, alignment: .trailing)
        }
        .frame(height: geometry.closedNotchHeight, alignment: .center)
    }

    private func statusText(_ snapshot: BatterySnapshot) -> String {
        if snapshot.isCharging { return "Charging battery" }
        if snapshot.isPluggedIn {
            return snapshot.currentCapacity < snapshot.maxCapacity ? "Not charging" : "Full charge"
        }
        return "Unplugged"
    }
}

/// The Battery settings page contributed as a settings destination.
public struct BatterySettingsView: View {
    public init() {}

    public var body: some View {
        Form {
            Section {
                toggle(
                    "Show battery indicator",
                    get: { BatterySettings.showBatteryIndicator },
                    set: { BatterySettings.showBatteryIndicator = $0 }
                )
                toggle(
                    "Show power status notifications",
                    get: { BatterySettings.showPowerStatusNotifications },
                    set: { BatterySettings.showPowerStatusNotifications = $0 }
                )
            } header: {
                Text("General")
            }
            Section {
                toggle(
                    "Show battery percentage",
                    get: { BatterySettings.showBatteryPercentage },
                    set: { BatterySettings.showBatteryPercentage = $0 }
                )
                toggle(
                    "Show power status icons",
                    get: { BatterySettings.showPowerStatusIcons },
                    set: { BatterySettings.showPowerStatusIcons = $0 }
                )
            } header: {
                Text("Battery Information")
            }
        }
    }

    private func toggle(
        _ title: String,
        get: @escaping () -> Bool,
        set: @escaping (Bool) -> Void
    ) -> some View {
        Toggle(title, isOn: Binding(get: get, set: set))
    }
}