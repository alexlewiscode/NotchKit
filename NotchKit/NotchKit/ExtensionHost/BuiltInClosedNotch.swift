//
//  BuiltInClosedNotch.swift
//  NotchKit
//
//  Declares the built-in closed-notch contributions and builds render snapshots.
//

import Defaults
import NotchExtensionSDK
import NotchExtensionRuntime
import SwiftUI

/// Factory for the built-in closed-notch contributions.
///
/// The four built-in contents previously competed through an `if`/`else if`
/// chain in `ContentView`. They now declare a region, priority, availability,
/// and optional preferred chin width, and are selected deterministically by
/// `ClosedNotchSelection`. Priorities reproduce the previous branch order.
@MainActor
enum BuiltInClosedNotch {
    static func contributions(
        vm: BoringViewModel,
        hoverAnimation: Binding<Bool>,
        gestureProgress: Binding<CGFloat>
    ) -> [ClosedNotchContribution] {
        [
            inlineHUD(vm: vm, hoverAnimation: hoverAnimation, gestureProgress: gestureProgress),
            music(vm: vm, gestureProgress: gestureProgress),
            idleFace(vm: vm),
        ]
    }

    static func snapshot(
        vm: BoringViewModel,
        coordinator: BoringViewCoordinator
    ) -> ClosedNotchRenderSnapshot {
        let musicManager = MusicManager.shared
        let isMediaActive = musicManager.isPlaying || !musicManager.isPlayerIdle

        return ClosedNotchRenderSnapshot(
            isNotchOpen: vm.notchState == .open,
            isHiddenOnClosed: vm.hideOnClosed,
            isMediaActive: isMediaActive,
            isMediaIdle: musicManager.isPlayerIdle,
            expandingViewKind: expandingViewKind(coordinator.expandingView.type),
            isExpandingViewShown: coordinator.expandingView.show,
            sneakPeekKind: sneakPeekKind(coordinator.sneakPeek.type),
            isSneakPeekVisible: coordinator.sneakPeek.show,
            flags: [
                "inlineHUD": Defaults[.inlineHUD],
                "musicLiveActivityEnabled": coordinator.musicLiveActivityEnabled,
                "showNotHumanFace": Defaults[.showNotHumanFace],
            ]
        )
    }

    // MARK: - Contributions

    private static func inlineHUD(
        vm: BoringViewModel,
        hoverAnimation: Binding<Bool>,
        gestureProgress: Binding<CGFloat>
    ) -> ClosedNotchContribution {
        ClosedNotchContribution(
            id: BuiltInExtensionIDs.inlineHUDContribution,
            extensionID: BuiltInExtensionIDs.home,
            region: .exclusion,
            priority: 300,
            tieBreaker: "inline-hud",
            isAvailable: { snapshot in
                !snapshot.isNotchOpen
                    && snapshot.isSneakPeekVisible
                    && snapshot.flag("inlineHUD")
                    && snapshot.sneakPeekKind != "music"
                    && snapshot.sneakPeekKind != "battery"
            },
            makeView: {
                AnyView(
                    InlineHUDContent(
                        hoverAnimation: hoverAnimation,
                        gestureProgress: gestureProgress
                    )
                )
            },
            preferredChinWidth: { _ in vm.closedNotchSize.width }
        )
    }

    private static func music(
        vm: BoringViewModel,
        gestureProgress: Binding<CGFloat>
    ) -> ClosedNotchContribution {
        ClosedNotchContribution(
            id: BuiltInExtensionIDs.musicContribution,
            extensionID: BuiltInExtensionIDs.home,
            region: .exclusion,
            priority: 200,
            tieBreaker: "music",
            isAvailable: { snapshot in
                !snapshot.isNotchOpen
                    && (!snapshot.isExpandingViewShown || snapshot.expandingViewKind == "music")
                    && snapshot.isMediaActive
                    && snapshot.flag("musicLiveActivityEnabled")
                    && !snapshot.isHiddenOnClosed
            },
            makeView: {
                AnyView(
                    MusicLiveActivityContent(gestureProgress: gestureProgress)
                        .frame(alignment: .center)
                )
            },
            preferredChinWidth: { _ in extendedChinWidth(for: vm) }
        )
    }

    private static func idleFace(vm: BoringViewModel) -> ClosedNotchContribution {
        ClosedNotchContribution(
            id: BuiltInExtensionIDs.idleFaceContribution,
            extensionID: BuiltInExtensionIDs.home,
            region: .exclusion,
            priority: 100,
            tieBreaker: "idle-face",
            isAvailable: { snapshot in
                !snapshot.isNotchOpen
                    && !snapshot.isExpandingViewShown
                    && !snapshot.isMediaActive
                    && snapshot.isMediaIdle
                    && snapshot.flag("showNotHumanFace")
                    && !snapshot.isHiddenOnClosed
            },
            makeView: { AnyView(IdleFaceContent()) },
            preferredChinWidth: { _ in extendedChinWidth(for: vm) }
        )
    }

    // MARK: - Helpers

    private static func extendedChinWidth(for vm: BoringViewModel) -> CGFloat {
        let base = vm.closedNotchSize.width
        let extra = 2 * max(0, vm.effectiveClosedNotchHeight - 12) + 20
        return base + extra
    }

    private static func expandingViewKind(_ type: SneakContentType) -> String {
        switch type {
        case .brightness: return "brightness"
        case .volume: return "volume"
        case .backlight: return "backlight"
        case .music: return "music"
        case .mic: return "mic"
        case .battery: return "battery"
        case .download: return "download"
        }
    }

    private static func sneakPeekKind(_ type: SneakContentType) -> String {
        expandingViewKind(type)
    }
}