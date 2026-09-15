//
//  CalendarManager.swift
//  NotchKit
//
//  Created by Harsh Vardhan  Goswami  on 08/09/24.
//

import Combine
import Defaults
import EventKit
import SwiftUI

extension Notification.Name {
    /// Posted when calendar/reminder selection changes in settings.
    static let calendarSelectionChanged = Notification.Name("notchkit.calendarSelectionChanged")
    /// Posted when calendar/reminder authorization changes (for example after an
    /// explicit grant), so a running feature refreshes its lists and events.
    static let calendarAuthorizationChanged = Notification.Name("notchkit.calendarAuthorizationChanged")
}

/// Persistence and change signal for calendar selection.
///
/// Injected so the settings provider and a running `CalendarManager` share state
/// without either creating the other, and so tests never touch personal
/// preferences. The store persists the raw `calendarSelectionState` key
/// unchanged.
protocol CalendarSelectionStore: AnyObject {
    var selectionState: CalendarSelectionState { get set }
    func notifySelectionChanged()
}

/// Production store backed by `Defaults[.calendarSelectionState]`.
final class DefaultsCalendarSelectionStore: CalendarSelectionStore {
    var selectionState: CalendarSelectionState {
        get { Defaults[.calendarSelectionState] }
        set { Defaults[.calendarSelectionState] = newValue }
    }

    func notifySelectionChanged() {
        NotificationCenter.default.post(name: .calendarSelectionChanged, object: nil)
    }
}

// MARK: - CalendarManager

@MainActor
class CalendarManager: ObservableObject {
    static let shared = CalendarManager()

    /// Test instrumentation: how many managers this process has constructed.
    /// Settings must never construct a manager, so provider tests assert this
    /// does not change.
    private(set) static var instanceCount = 0

    @Published var currentWeekStartDate: Date
    @Published var events: [EventModel] = []
    @Published var allCalendars: [CalendarModel] = []
    @Published var eventCalendars: [CalendarModel] = []
    @Published var reminderLists: [CalendarModel] = []
    @Published var selectedCalendarIDs: Set<String> = []
    @Published var calendarAuthorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var reminderAuthorizationStatus: EKAuthorizationStatus = .notDetermined
    private(set) var selectedCalendars: [CalendarModel] = []

    private let calendarService: CalendarServiceProviding
    private let selectionStore: CalendarSelectionStore

    private var eventStoreChangedObserver: NSObjectProtocol?
    private var selectionChangedObserver: NSObjectProtocol?
    private var authorizationChangedObserver: NSObjectProtocol?
    /// Feature-owned work, cancelled on `stop()` so a disabled feature leaves no
    /// in-flight refresh behind.
    private var refreshTasks: [Task<Void, Never>] = []

    /// Whether the feature is currently running. `init` is inert; only `start()`
    /// registers observers and loads data.
    private(set) var isActive = false

    /// List loading and event refreshing are ordered independently. A selection
    /// or date change must never invalidate an in-flight list load (which would
    /// leave the manager with empty lists), and an older event load must never
    /// overwrite a newer one, even when both share a date or selection.
    private var listGeneration = 0
    private var eventGeneration = 0

    private init() {
        Self.instanceCount += 1
        self.calendarService = CalendarService()
        self.selectionStore = DefaultsCalendarSelectionStore()
        self.currentWeekStartDate = CalendarManager.startOfDay(Date())
    }

    /// Seam for tests: inject the calendar service and selection persistence.
    ///
    /// The injected manager is considered running so its change observers
    /// propagate, matching production `start()`.
    init(calendarService: CalendarServiceProviding, selectionStore: CalendarSelectionStore) {
        Self.instanceCount += 1
        self.calendarService = calendarService
        self.selectionStore = selectionStore
        self.currentWeekStartDate = CalendarManager.startOfDay(Date())
        self.isActive = true
        setupObservers()
    }

    /// Starts the feature: registers change observers and loads lists once.
    ///
    /// Safe to call more than once; the second call is a no-op. The production
    /// singleton is inert under a test host.
    func start() {
        guard !TestHostPolicy.isActive else { return }
        guard !isActive else { return }
        isActive = true
        setupObservers()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.reloadCalendarAndReminderLists()
        }
        refreshTasks.append(task)
    }

    /// Stops the feature: removes observers, cancels owned work, and clears the
    /// presented data. Never touches persisted selections or preferences.
    func stop() {
        guard isActive else { return }
        isActive = false
        teardownObservers()
        refreshTasks.forEach { $0.cancel() }
        refreshTasks.removeAll()
        listGeneration += 1
        eventGeneration += 1
        events = []
        allCalendars = []
        eventCalendars = []
        reminderLists = []
        selectedCalendars = []
    }

    private func teardownObservers() {
        if let eventStoreChangedObserver {
            NotificationCenter.default.removeObserver(eventStoreChangedObserver)
            self.eventStoreChangedObserver = nil
        }
        if let selectionChangedObserver {
            NotificationCenter.default.removeObserver(selectionChangedObserver)
            self.selectionChangedObserver = nil
        }
        if let authorizationChangedObserver {
            NotificationCenter.default.removeObserver(authorizationChangedObserver)
            self.authorizationChangedObserver = nil
        }
    }

    deinit {
        // `deinit` is nonisolated, so remove observers directly rather than
        // calling the main-actor-isolated helper.
        if let eventStoreChangedObserver {
            NotificationCenter.default.removeObserver(eventStoreChangedObserver)
        }
        if let selectionChangedObserver {
            NotificationCenter.default.removeObserver(selectionChangedObserver)
        }
        if let authorizationChangedObserver {
            NotificationCenter.default.removeObserver(authorizationChangedObserver)
        }
    }

    private func setupObservers() {
        eventStoreChangedObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isActive else { return }
            Task {
                await self.reloadCalendarAndReminderLists()
            }
        }

        // A running feature reacts to selection changes made in settings even
        // though the settings page never touches this manager.
        selectionChangedObserver = NotificationCenter.default.addObserver(
            forName: .calendarSelectionChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isActive else { return }
            Task {
                await self.refreshSelectionAndEvents()
            }
        }

        authorizationChangedObserver = NotificationCenter.default.addObserver(
            forName: .calendarAuthorizationChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isActive else { return }
            Task {
                await self.refreshAfterAuthorizationChange()
            }
        }
    }

    @MainActor
    func reloadCalendarAndReminderLists() async {
        listGeneration += 1
        let generation = listGeneration
        let all = await calendarService.calendars()
        guard generation == listGeneration else { return }
        applyCalendars(all)
        // Always recompute events after a fresh list: a selection change may have
        // arrived while the lists were loading.
        await refreshEvents()
    }

    private func applyCalendars(_ all: [CalendarModel]) {
        self.eventCalendars = all.filter { !$0.isReminder }
        self.reminderLists = all.filter { $0.isReminder }
        self.allCalendars = all
        updateSelectedCalendars()
    }

    /// Rebuilds the effective selection from the shared store and refreshes
    /// events. Called when the settings page changes the selection. This does not
    /// touch list loading, so a concurrent initial load still completes.
    func refreshSelectionAndEvents() async {
        updateSelectedCalendars()
        await refreshEvents()
    }

    /// Reloads lists, selection, and events after an authorization change such
    /// as an explicit grant on the settings page.
    func refreshAfterAuthorizationChange() async {
        refreshCalendarAuthorizationStatus()
        listGeneration += 1
        let generation = listGeneration
        let all = await calendarService.calendars()
        guard generation == listGeneration else { return }
        applyCalendars(all)
        await refreshEvents()
    }

    func refreshCalendarAuthorizationStatus() {
        calendarAuthorizationStatus = calendarService.authorizationStatus(for: .event)
        reminderAuthorizationStatus = calendarService.authorizationStatus(for: .reminder)
    }

    func updateSelectedCalendars() {
        switch selectionStore.selectionState {
        case .all:
            selectedCalendarIDs = Set(allCalendars.map { $0.id })
        case .selected(let identifiers):
            selectedCalendarIDs = identifiers
        }

        selectedCalendars = allCalendars.filter { selectedCalendarIDs.contains($0.id) }
    }

    static func startOfDay(_ date: Date) -> Date {
        return Calendar.current.startOfDay(for: date)
    }

    func updateCurrentDate(_ date: Date) async {
        currentWeekStartDate = Calendar.current.startOfDay(for: date)
        await refreshEvents()
    }

    private func refreshEvents() async {
        eventGeneration += 1
        let generation = eventGeneration
        let calendarIDs = selectedCalendars.map { $0.id }
        let start = currentWeekStartDate
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let eventsResult = await calendarService.events(
            from: start,
            to: end,
            calendars: calendarIDs
        )
        guard generation == eventGeneration else { return }
        self.events = eventsResult
    }

    func setReminderCompleted(reminderID: String, completed: Bool) async {
        await calendarService.setReminderCompleted(reminderID: reminderID, completed: completed)
        // Refresh events after updating
        await refreshEvents()
    }
}
