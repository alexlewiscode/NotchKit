//
//  LegacySettingsDataProviders.swift
//  NotchKit
//
//  Page-scoped configuration data providers for the host-owned legacy feature
//  settings pages.
//
//  These deliberately do not touch the long-lived feature services
//  (`CalendarManager.shared`, `QuickShareService.shared`). They read status and
//  load configuration data only while their page is visible, and expose explicit
//  user-triggered actions for anything that requests access or discovers
//  providers.
//

import AppKit
@preconcurrency import EventKit
import Defaults
import Foundation
import SwiftUI

// MARK: - Calendar & Reminders

/// Reads calendar/reminder authorization status and loadable lists without
/// requesting access. Access is requested only through the explicit methods.
@MainActor
final class CalendarSettingsDataProvider: ObservableObject {
    @Published private(set) var eventAuthorization: EKAuthorizationStatus = .notDetermined
    @Published private(set) var reminderAuthorization: EKAuthorizationStatus = .notDetermined
    @Published private(set) var eventCalendars: [CalendarModel] = []
    @Published private(set) var reminderLists: [CalendarModel] = []
    @Published private(set) var isLoading = false
    @Published private(set) var selectedCalendarIDs: Set<String> = []

    private let service: CalendarServiceProviding
    private let selectionStore: CalendarSelectionStore
    private var lastEventAuthorization: EKAuthorizationStatus?
    private var lastReminderAuthorization: EKAuthorizationStatus?
    /// Guards superseded list loads so a slower, older load cannot overwrite a
    /// newer one.
    private var loadGeneration = 0

    init(
        service: CalendarServiceProviding = CalendarService(),
        selectionStore: CalendarSelectionStore = DefaultsCalendarSelectionStore()
    ) {
        self.service = service
        self.selectionStore = selectionStore
    }

    /// All calendars and reminder lists currently loaded.
    var allCalendars: [CalendarModel] { eventCalendars + reminderLists }

    /// Reads the current TCC status only. Never requests access.
    func refreshStatuses() {
        eventAuthorization = EKEventStore.authorizationStatus(for: .event)
        reminderAuthorization = EKEventStore.authorizationStatus(for: .reminder)
        lastEventAuthorization = eventAuthorization
        lastReminderAuthorization = reminderAuthorization
    }

    /// Loads the lists visible to the current authorization. Safe to call when
    /// access is not granted: it yields an empty list.
    func loadLists() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        let all = await service.calendars()
        guard generation == loadGeneration else { return }
        isLoading = false
        eventCalendars = all.filter { !$0.isReminder }
        reminderLists = all.filter { $0.isReminder }
        reloadSelection()
    }

    /// Explicit user action: requests calendar access, then reloads if granted.
    func requestEventAccess() async {
        if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            _ = try? await service.requestAccess(to: .event)
        }
        refreshStatuses()
        await loadLists()
        NotificationCenter.default.post(name: .calendarAuthorizationChanged, object: nil)
    }

    /// Explicit user action: requests reminder access, then reloads if granted.
    func requestReminderAccess() async {
        if EKEventStore.authorizationStatus(for: .reminder) == .notDetermined {
            _ = try? await service.requestAccess(to: .reminder)
        }
        refreshStatuses()
        await loadLists()
        NotificationCenter.default.post(name: .calendarAuthorizationChanged, object: nil)
    }

    /// Re-reads status and lists after the user returns from System Settings,
    /// and signals a running feature only when the authorization actually
    /// changed so the page does not spam refreshes.
    func refreshAfterReturningToApp() async {
        let previousEvent = lastEventAuthorization
        let previousReminder = lastReminderAuthorization
        eventAuthorization = EKEventStore.authorizationStatus(for: .event)
        reminderAuthorization = EKEventStore.authorizationStatus(for: .reminder)
        let changed = eventAuthorization != previousEvent || reminderAuthorization != previousReminder
        lastEventAuthorization = eventAuthorization
        lastReminderAuthorization = reminderAuthorization

        if eventAuthorization == .fullAccess || reminderAuthorization == .fullAccess {
            await loadLists()
        }
        if changed {
            NotificationCenter.default.post(name: .calendarAuthorizationChanged, object: nil)
        }
    }

    func isSelected(_ calendar: CalendarModel) -> Bool {
        selectedCalendarIDs.contains(calendar.id)
    }

    /// Preserves the historical `calendarSelectionState` semantics and signals a
    /// running feature through the shared store.
    func setSelected(_ calendar: CalendarModel, isSelected: Bool) {
        let all = allCalendars
        let updated = CalendarSelectionState.toggling(
            calendar.id,
            isSelected: isSelected,
            allIDs: Set(all.map(\.id)),
            from: selectionStore.selectionState
        )
        selectionStore.selectionState = updated
        reloadSelection()
        selectionStore.notifySelectionChanged()
    }

    private func reloadSelection() {
        switch selectionStore.selectionState {
        case .all:
            selectedCalendarIDs = Set(allCalendars.map(\.id))
        case .selected(let identifiers):
            selectedCalendarIDs = identifiers
        }
    }
}

// MARK: - Shelf Quick Share

/// Discovers available sharing providers for the Shelf settings page.
///
/// Provider discovery is legitimate configuration work, but it must be scoped to
/// the visible page and cancelled when the page closes. This source does not
/// touch `QuickShareService.shared`, so it never starts Shelf's drag or observer
/// services.
@MainActor
final class ShelfShareProviderDataSource: ObservableObject {
    @Published private(set) var providers: [QuickShareProvider] = []
    @Published private(set) var isLoading = false
    @Published private(set) var didLoad = false

    private var discoveryTask: Task<Void, Never>?

    /// Starts (or restarts) discovery. Cancels any in-flight discovery first.
    func load() {
        discoveryTask?.cancel()
        isLoading = true
        discoveryTask = Task { @MainActor [weak self] in
            let finder = ShareServiceFinder()
            let testItems: [Any] = [
                URL(string: "http://example.com") ?? URL(fileURLWithPath: "/"),
                "Test Text" as NSString,
            ]
            let services = await finder.findApplicableServices(for: testItems)
            guard !Task.isCancelled, let self else { return }

            var result: [QuickShareProvider] = []
            for service in services {
                let provider = QuickShareProvider(
                    id: service.title,
                    imageData: service.image.tiffRepresentation,
                    supportsRawText: service.canPerform(withItems: ["Test Text"])
                )
                if !result.contains(provider) { result.append(provider) }
            }
            if let airDropIndex = result.firstIndex(where: { $0.id == "AirDrop" }) {
                let airDrop = result.remove(at: airDropIndex)
                result.insert(airDrop, at: 0)
            }
            if !result.contains(where: { $0.id == "System Share Menu" }) {
                result.append(
                    QuickShareProvider(id: "System Share Menu", imageData: nil, supportsRawText: true)
                )
            }
            self.providers = result
            self.isLoading = false
            self.didLoad = true
        }
    }

    /// Cancels discovery when the page closes.
    func cancel() {
        discoveryTask?.cancel()
        discoveryTask = nil
        isLoading = false
    }

    func selectedProvider(id: String) -> QuickShareProvider? {
        providers.first { $0.id == id }
    }

    /// Guarantees the currently persisted provider is selectable even before
    /// discovery completes, so a stored choice is never silently reset.
    func providersIncludingSelected(id: String) -> [QuickShareProvider] {
        guard !providers.contains(where: { $0.id == id }) else { return providers }
        return [QuickShareProvider(id: id, imageData: nil, supportsRawText: true)] + providers
    }
}
