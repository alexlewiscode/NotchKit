//
//  MediaKeyInterceptor.swift
//  NotchKit
//
//  Created by Alexander on 2025-11-23.

import Foundation
import AppKit
import ApplicationServices
import Defaults
import AVFoundation
import NotchExtensionSDK
import os

private let kSystemDefinedEventType = CGEventType(rawValue: 14)!

@MainActor
final class MediaKeyInterceptor: HUDIntercepting {
    static let shared = MediaKeyInterceptor()
    
    private enum NXKeyType: Int {
        case soundUp = 0
        case soundDown = 1
        case brightnessUp = 2
        case brightnessDown = 3
        case mute = 7
        case keyboardBrightnessUp = 21
        case keyboardBrightnessDown = 22
    }
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let step: Float = 1.0 / 16.0
    private var audioPlayer: AVAudioPlayer?
    /// Incremented by `stop()`, so a start that is mid-flight can detect that it
    /// was superseded and bail out without installing a tap.
    private var startToken = 0
    private var shouldRun = false

    /// Input-access diagnostics (preflights). Never used as a gate here: the tap
    /// attempt below is the authoritative capability test.
    private let inputAccess: InputAccessAuthorizing
    /// Test seam: replaces the real `CGEvent.tapCreate` installation.
    private let installOverride: (() -> Bool)?
    /// Test seam: replaces re-enabling the installed tap after Core Graphics
    /// disables it.
    private let reenableOverride: (() -> Bool)?
    private let recoveryDelayNanoseconds: UInt64

    private let logger = Logger(
        subsystem: NotchKitIdentity.bundleIdentifier,
        category: "MediaKeyInterceptor"
    )

    init(
        inputAccess: InputAccessAuthorizing = SystemInputAccessAuthorization(),
        installOverride: (() -> Bool)? = nil,
        reenableOverride: (() -> Bool)? = nil,
        recoveryDelayNanoseconds: UInt64 = 1_000_000_000
    ) {
        self.inputAccess = inputAccess
        self.installOverride = installOverride
        self.reenableOverride = reenableOverride
        self.recoveryDelayNanoseconds = recoveryDelayNanoseconds
    }

    /// Whether an event tap is currently installed.
    private(set) var isRunning = false

    // MARK: - Event Tap

    /// Attempts to install an event tap.
    ///
    /// Returns whether a tap is running when this call finishes. This is a
    /// read-only status check: it never prompts. Concurrent calls are safe: a
    /// superseded start detects the token change and does not install, and a
    /// same-generation duplicate sees the tap already present rather than
    /// creating a second one.
    @discardableResult
    func start() async -> Bool {
        shouldRun = true
        let token = startToken
        return start(expectedToken: token)
    }

    private func start(expectedToken token: Int) -> Bool {
        guard shouldRun, token == startToken else { return isRunning }
        guard !isRunning else { return true }

        let installed = performInstall()
        guard shouldRun, token == startToken else {
            if installed { tearDownTap() }
            return false
        }
        if !installed {
            // `CGEvent.tapCreate` reports no specific cause, so log only the
            // context we actually have (identity + preflights).
            logger.error("Media-key tap unavailable (\(self.inputAccess.diagnostics, privacy: .public))")
        }
        return installed
    }

    private func performInstall() -> Bool {
        if let installOverride {
            isRunning = installOverride()
            return isRunning
        }
        guard !TestHostPolicy.isActive else { return false }

        if installTap() {
            logger.info("Media-key tap installed (session/default)")
            isRunning = true
            return true
        }
        logger.error("Media-key tap attempt failed (session/default)")
        isRunning = false
        return false
    }

    private func installTap() -> Bool {
        let mask = CGEventMask(1 << kSystemDefinedEventType.rawValue)
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, cgEvent, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(cgEvent) }
                let interceptor = Unmanaged<MediaKeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
                // This tap's run-loop source is installed on the main run loop.
                return MainActor.assumeIsolated {
                    interceptor.handleEvent(type: type, event: cgEvent)
                }
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        guard let tap else { return false }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        guard CGEvent.tapIsEnabled(tap: tap) else {
            tearDownTap()
            return false
        }
        return true
    }
    
    func stop() {
        shouldRun = false
        startToken &+= 1
        tearDownTap()
    }

    private func tearDownTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
        isRunning = false
    }
    
    // MARK: - Event Handling
    
    func handleEvent(type: CGEventType, event cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        guard isRunning else { return Unmanaged.passUnretained(cgEvent) }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            recoverDisabledTap(reason: type == .tapDisabledByTimeout ? "timeout" : "user input")
            return Unmanaged.passUnretained(cgEvent)
        }
        // Ensure the CGEvent has a valid type before converting to NSEvent
        guard cgEvent.type != .null else {
            return Unmanaged.passUnretained(cgEvent)
        }
        guard let nsEvent = NSEvent(cgEvent: cgEvent),
              nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(cgEvent)
        }
        
        let data1 = nsEvent.data1
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let stateByte = ((data1 & 0xFF00) >> 8)
        
        // 0xA = key down, 0xB = key up. Only handle key down.
        guard stateByte == 0xA,
              let keyType = NXKeyType(rawValue: keyCode) else {
            return Unmanaged.passUnretained(cgEvent)
        }
        
        let flags = nsEvent.modifierFlags
        let option = flags.contains(.option)
        let shift = flags.contains(.shift)
        let command = flags.contains(.command)
        
        // Handle option key action (without shift)
        if option && !shift {
            if handleOptionAction(for: keyType, command: command) {
                return nil
            }
        }
        
        // Handle normal key press
        handleKeyPress(keyType: keyType, option: option, shift: shift, command: command)
        return nil
    }

    private func recoverDisabledTap(reason: String) {
        let enabled: Bool
        if let reenableOverride {
            enabled = reenableOverride()
        } else if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
            enabled = CGEvent.tapIsEnabled(tap: eventTap)
        } else {
            enabled = false
        }

        guard enabled else {
            logger.error("Media-key tap recovery failed after \(reason, privacy: .public)")
            tearDownTap()
            scheduleReinstall()
            return
        }
        isRunning = true
        logger.info("Media-key tap recovered after \(reason, privacy: .public)")
    }

    private func scheduleReinstall() {
        let token = startToken
        Task { @MainActor [weak self] in
            guard let self else { return }
            while self.shouldRun, token == self.startToken {
                try? await Task.sleep(nanoseconds: self.recoveryDelayNanoseconds)
                guard self.shouldRun, token == self.startToken else { return }
                if self.start(expectedToken: token) {
                    self.logger.info("Media-key tap reinstalled after recovery failure")
                    return
                }
            }
        }
    }
    
    private func handleOptionAction(for keyType: NXKeyType, command: Bool) -> Bool {
        let action = Defaults[.optionKeyAction]
        
        switch action {
        case .openSettings:
            openSystemSettings(for: keyType, command: command)
            return true
        case .showHUD:
            showHUD(for: keyType, command: command)
            return true
        case .none:
            return true
        }
    }
    
    private func prepareAudioPlayerIfNeeded() {
        guard audioPlayer == nil else { return }

        let defaultPath = "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff"
        if FileManager.default.fileExists(atPath: defaultPath) {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: defaultPath))
                print("🔊 [MediaKeyInterceptor] Loaded default Bezel audio from: \(defaultPath)")
            } catch {
                print("⚠️ [MediaKeyInterceptor] Failed to init AVAudioPlayer with default path \(defaultPath): \(error.localizedDescription)")
            }
        } else {
            print("⚠️ [MediaKeyInterceptor] Default bezel audio not found at: \(defaultPath)")
        }

        if let player = audioPlayer {
            player.volume = 1.0
            player.numberOfLoops = 0
            player.prepareToPlay()
        }
    }

    private func playFeedbackSound() {
        guard let feedback = UserDefaults.standard.persistentDomain(forName: "NSGlobalDomain")?["com.apple.sound.beep.feedback"] as? Int,
              feedback == 1 else { return }

        prepareAudioPlayerIfNeeded()
        guard let player = audioPlayer else {
            print("⚠️ [MediaKeyInterceptor] No audio player available to play feedback sound")
            return
        }
        if let url = player.url {
            print("🔊 [MediaKeyInterceptor] Playing feedback sound from: \(url.path)")
        } else {
            print("🔊 [MediaKeyInterceptor] Playing feedback sound (no url available for AVAudioPlayer)")
        }
        if player.isPlaying {
            player.stop()
            player.currentTime = 0
        }
        player.play()
    }

    private func handleKeyPress(keyType: NXKeyType, option: Bool, shift: Bool, command: Bool) {
        let stepDivisor: Float = (option && shift) ? 4.0 : 1.0
        
        switch keyType {
        case .soundUp:
            Task { @MainActor in
                self.playFeedbackSound()
                VolumeManager.shared.increase(stepDivisor: stepDivisor)
            }
        case .soundDown:
            Task { @MainActor in
                self.playFeedbackSound()
                VolumeManager.shared.decrease(stepDivisor: stepDivisor)
            }
        case .mute:
            Task { @MainActor in
                VolumeManager.shared.toggleMuteAction()
            }
        case .brightnessUp, .keyboardBrightnessUp:
            let delta = step / stepDivisor
            adjustBrightness(delta: delta, keyboard: keyType == .keyboardBrightnessUp || command)
        case .brightnessDown, .keyboardBrightnessDown:
            let delta = -(step / stepDivisor)
            adjustBrightness(delta: delta, keyboard: keyType == .keyboardBrightnessDown || command)
        }
    }
    
    private func adjustBrightness(delta: Float, keyboard: Bool) {
        Task { @MainActor in
            if keyboard {
                KeyboardBacklightManager.shared.setRelative(delta: delta)
            } else {
                BrightnessManager.shared.setRelative(delta: delta)
            }
        }
    }
    
    private func showHUD(for keyType: NXKeyType, command: Bool) {
        Task { @MainActor in
            switch keyType {
            case .soundUp, .soundDown, .mute:
                let v = VolumeManager.shared.rawVolume
                BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .volume, value: CGFloat(v))
            case .brightnessUp, .brightnessDown:
                if command {
                    let v = KeyboardBacklightManager.shared.rawBrightness
                    BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .backlight, value: CGFloat(v))
                } else {
                    let v = BrightnessManager.shared.rawBrightness
                    BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .brightness, value: CGFloat(v))
                }
            case .keyboardBrightnessUp, .keyboardBrightnessDown:
                let v = KeyboardBacklightManager.shared.rawBrightness
                BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .backlight, value: CGFloat(v))
            }
        }
    }
    
    private func openSystemSettings(for keyType: NXKeyType, command: Bool) {
        let urlString: String
        
        switch keyType {
        case .soundUp, .soundDown, .mute:
            urlString = "x-apple.systempreferences:com.apple.preference.sound"
        case .brightnessUp, .brightnessDown:
            if command {
                urlString = "x-apple.systempreferences:com.apple.preference.keyboard"
            } else {
                urlString = "x-apple.systempreferences:com.apple.preference.displays"
            }
        case .keyboardBrightnessUp, .keyboardBrightnessDown:
            urlString = "x-apple.systempreferences:com.apple.preference.keyboard"
        }
        
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
