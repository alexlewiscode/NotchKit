//
//  MusicSlotConfigurationView.swift
//  NotchKit
//
//  Created by Alexander on 2025-11-17.
//

import Defaults
import SwiftUI
import UniformTypeIdentifiers

struct MusicSlotConfigurationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Default(.musicControlSlots) private var musicControlSlots
    @ObservedObject private var musicManager = MusicManager.shared
    @State private var draggedSlot: MusicControlButton?

    private let fixedSlotCount: Int = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            slotConfigurationSection

            HStack(spacing: 8) {
                Text("Changes are saved automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset to Defaults") {
                    withAnimation(reduceMotion ? nil : .default) {
                        musicControlSlots = MusicControlButton.defaultLayout
                    }
                }
                .accessibilityHint("Restores all five media control slots")
            }
        }
        .padding(16)
        .onAppear {
            ensureSlotCapacity(fixedSlotCount)
        }
    }

    private var previewSection: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 6) {
                ForEach(0..<fixedSlotCount, id: \.self) { index in
                    let slot = slotValue(at: index)
                    Group {
                        if slot != .none {
                            slotPreview(for: slot)
                                .frame(maxWidth: 44)
                                .onDrag {
                                    DispatchQueue.main.async { draggedSlot = slot }
                                    return NSItemProvider(object: NSString(string: "slot:\(index)"))
                                }
                                .onDrop(of: [UTType.plainText.identifier], isTargeted: nil) { providers in
                                    let handled = handleDrop(providers, toIndex: index)
                                    DispatchQueue.main.async { draggedSlot = nil }
                                    return handled
                                }
                                .accessibilityLabel("Slot \(index + 1), \(slot.label)")
                        } else {
                            slotPreview(for: slot)
                                .frame(maxWidth: 44)
                                .onDrop(of: [UTType.plainText.identifier], isTargeted: nil) { providers in
                                    let handled = handleDrop(providers, toIndex: index)
                                    DispatchQueue.main.async { draggedSlot = nil }
                                    return handled
                                }
                                .accessibilityLabel("Slot \(index + 1), empty")
                        }
                    }
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .frame(width: 56, height: 56)

                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.primary)
                }
                .cornerRadius(10)
                .contentShape(RoundedRectangle(cornerRadius: 10))
                .onDrop(of: [UTType.plainText.identifier], isTargeted: nil) { providers in
                    return handleDropOnTrash(providers)
                }
                .accessibilityHidden(true)

                Text("Clear slot")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: 72)
            }
        }
    }

    private var slotConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Layout Preview")
                .font(.subheadline.weight(.semibold))
            previewSection

            Divider()

            VStack(spacing: 0) {
                ForEach(0..<fixedSlotCount, id: \.self) { index in
                    accessibleSlotRow(for: index)
                    if index < fixedSlotCount - 1 {
                        Divider().padding(.leading, 34)
                    }
                }
            }
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 8))

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Control Palette")
                    .font(.subheadline.weight(.semibold))
                Text("Click a control to fill the first empty slot, or drag it to a specific slot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(MusicControlButton.pickerOptions, id: \.self) { control in
                            VStack(spacing: 6) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(NSColor.controlBackgroundColor))
                                        .frame(width: 44, height: 44)

                                    if control != .none {
                                        Image(systemName: control.iconName)
                                            .font(.system(size: control.prefersLargeScale ? 18 : 15, weight: .medium))
                                            .foregroundStyle(control == .none ? Color.secondary : Color.primary)
                                            .frame(width: 28, height: 28)
                                    }
                                }
                                .cornerRadius(8)
                                .contentShape(RoundedRectangle(cornerRadius: 8))
                                .onDrag {
                                    return NSItemProvider(object: NSString(string: "control:\(control.rawValue)"))
                                }
                                .onTapGesture {
                                    addControlFromPalette(control)
                                }
                                .accessibilityHidden(true)

                                Text(control.label)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 60)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Add \(control.label)")
                            .accessibilityHint("Fills the first empty slot, or replaces slot one")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction {
                                addControlFromPalette(control)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.visible)
            }
        }
    }

    private func accessibleSlotRow(for index: Int) -> some View {
        let currentSlot = slotValue(at: index)

        return HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.body.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Image(systemName: currentSlot == .none ? "square.dashed" : currentSlot.iconName)
                .frame(width: 20)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Picker("Slot \(index + 1)", selection: slotBinding(for: index)) {
                ForEach([.none] + MusicControlButton.pickerOptions, id: \.self) { control in
                    Label(control.label, systemImage: control == .none ? "square.dashed" : control.iconName)
                        .tag(control)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 210)

            Spacer()

            Button {
                moveSlot(from: index, to: index - 1)
            } label: {
                Image(systemName: "arrow.left")
            }
            .disabled(index == 0)
            .help("Move slot \(index + 1) left")
            .accessibilityLabel("Move slot \(index + 1) left")

            Button {
                moveSlot(from: index, to: index + 1)
            } label: {
                Image(systemName: "arrow.right")
            }
            .disabled(index == fixedSlotCount - 1)
            .help("Move slot \(index + 1) right")
            .accessibilityLabel("Move slot \(index + 1) right")

            Button {
                updateSlot(.none, at: index)
            } label: {
                Image(systemName: "xmark")
            }
            .disabled(currentSlot == .none)
            .help("Clear slot \(index + 1)")
            .accessibilityLabel("Clear slot \(index + 1)")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func slotPreview(for slot: MusicControlButton) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .frame(width: 44, height: 44)

            if slot != .none {
                Image(systemName: slot.iconName)
                    .font(.system(size: slot.prefersLargeScale ? 18 : 15, weight: .medium))
                    .foregroundStyle(previewIconColor(for: slot))
                    .frame(width: 28, height: 28)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Color.secondary.opacity(0.3))
                    .frame(width: 32, height: 32)
            }
        }
        .cornerRadius(8)
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    private func previewIconColor(for slot: MusicControlButton) -> Color {
        switch slot {
        case .shuffle:
            return musicManager.isShuffled ? .red : .primary
        case .repeatMode:
            return musicManager.repeatMode != .off ? .red : .primary
        case .favorite:
            return musicManager.isFavoriteTrack ? .red : .primary
        case .playPause:
            return .primary
        default:
            return .primary
        }
    }

    private func ensureSlotCapacity(_ target: Int) {
        guard target > musicControlSlots.count else { return }
        let missing = target - musicControlSlots.count
        musicControlSlots.append(contentsOf: Array(repeating: .none, count: missing))
    }

    private func slotBinding(for index: Int) -> Binding<MusicControlButton> {
        Binding(
            get: { slotValue(at: index) },
            set: { newValue in assignControl(newValue, to: index) }
        )
    }

    private func moveSlot(from source: Int, to destination: Int) {
        guard source != destination,
              (0..<fixedSlotCount).contains(source),
              (0..<fixedSlotCount).contains(destination) else { return }
        withAnimation(reduceMotion ? nil : .default) {
            var slots = musicControlSlots
            slots.swapAt(source, destination)
            musicControlSlots = slots
        }
    }

    private func assignControl(_ control: MusicControlButton, to index: Int) {
        var slots = musicControlSlots
        if control != .none, let existing = slots.firstIndex(of: control), existing != index {
            slots[existing] = .none
        }
        if index >= slots.count {
            slots.append(contentsOf: Array(repeating: .none, count: index - slots.count + 1))
        }
        slots[index] = control
        musicControlSlots = slots
    }

    private func addControlFromPalette(_ control: MusicControlButton) {
        if let index = musicControlSlots.firstIndex(of: .none) {
            updateSlot(control, at: index)
        } else {
            withAnimation(reduceMotion ? nil : .default) {
                updateSlot(control, at: 0)
            }
        }
    }

    private func slotValue(at index: Int) -> MusicControlButton {
        guard musicControlSlots.indices.contains(index) else { return .none }
        return musicControlSlots[index]
    }

    private func handleDrop(_ providers: [NSItemProvider], toIndex: Int) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSString.self) {
                provider.loadObject(ofClass: NSString.self) { item, error in
                    // item may be an NSString (which conforms to NSItemProviderReading) or other reading type
                    if let nsstring = item as? NSString {
                        let raw = nsstring as String
                        DispatchQueue.main.async {
                            processDropString(raw, toIndex: toIndex)
                        }
                    } else if let str = item as? String {
                        DispatchQueue.main.async {
                            processDropString(str, toIndex: toIndex)
                        }
                    }
                }
                return true
            }
        }
        return false
    }

    private func handleDropOnTrash(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSString.self) {
                provider.loadObject(ofClass: NSString.self) { item, error in
                    if let nsstring = item as? NSString {
                        let raw = nsstring as String
                        DispatchQueue.main.async {
                            if raw.hasPrefix("slot:") {
                                // parse source slot index and clear it
                                let from = Int(raw.replacingOccurrences(of: "slot:", with: "")) ?? -1
                                guard from >= 0 && from < fixedSlotCount else { return }
                                var slots = musicControlSlots
                                if from < slots.count {
                                    slots[from] = .none
                                    musicControlSlots = slots
                                }
                            }
                        }
                    } else if let str = item as? String {
                        DispatchQueue.main.async {
                            if str.hasPrefix("slot:") {
                                let from = Int(str.replacingOccurrences(of: "slot:", with: "")) ?? -1
                                guard from >= 0 && from < fixedSlotCount else { return }
                                var slots = musicControlSlots
                                if from < slots.count {
                                    slots[from] = .none
                                    musicControlSlots = slots
                                }
                            }
                        }
                    }
                }
                return true
            }
        }
        return false
    }

    private func processDropString(_ raw: String, toIndex: Int) {
        if raw.hasPrefix("slot:") {
            let from = Int(raw.replacingOccurrences(of: "slot:", with: "")) ?? -1
            guard from >= 0 && from < fixedSlotCount else { return }
            var slots = musicControlSlots
            if from < slots.count && toIndex < slots.count {
                slots.swapAt(from, toIndex)
                musicControlSlots = slots
            }
        } else if raw.hasPrefix("control:") {
            let val = raw.replacingOccurrences(of: "control:", with: "")
            if let control = MusicControlButton(rawValue: val) {
                // If this control already exists in another slot, clear that original slot
                var slots = musicControlSlots
                if let existing = slots.firstIndex(of: control), existing != toIndex {
                    slots[existing] = .none
                    musicControlSlots = slots
                }

                updateSlot(control, at: toIndex)
            }
        }
    }

    private func updateSlot(_ value: MusicControlButton, at index: Int) {
        var slots = musicControlSlots
        if index >= slots.count {
            slots.append(contentsOf: Array(repeating: .none, count: index - slots.count + 1))
        }
        slots[index] = value
        musicControlSlots = slots
    }
}
