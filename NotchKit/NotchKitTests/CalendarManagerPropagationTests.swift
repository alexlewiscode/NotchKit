//
//  CalendarManagerPropagationTests.swift
//  NotchKitTests
//
//  Observable behaviour: a selection change made through the settings provider
//  must reach a running CalendarManager, and a manager created later must read
//  the latest persisted selection.
//

import EventKit
import XCTest
@testable import NotchKit

@MainActor
final class CalendarManagerPropagationTests: XCTestCase {

    func testSelectionChangeReachesRunningFeature() async {
        let service = FakeCalendarService()
        service.calendarResults = [[makeCalendar("a"), makeCalendar("b")]]
        let store = InMemoryCalendarSelectionStore(.all)

        let manager = CalendarManager(calendarService: service, selectionStore: store)
        await manager.reloadCalendarAndReminderLists()
        XCTAssertEqual(manager.selectedCalendars.map(\.id).sorted(), ["a", "b"])

        // The settings provider shares only the store, never the manager.
        let provider = CalendarSettingsDataProvider(service: service, selectionStore: store)
        await provider.loadLists()
        provider.setSelected(makeCalendar("a"), isSelected: false)

        // Wait for the notification-driven refresh to run on the main actor.
        await waitUntil { manager.selectedCalendars.map(\.id) == ["b"] }

        XCTAssertFalse(manager.selectedCalendarIDs.contains("a"))
        XCTAssertTrue(manager.selectedCalendarIDs.contains("b"))
        XCTAssertEqual(manager.selectedCalendars.map(\.id), ["b"])
    }

    func testManagerCreatedLaterReadsLatestSelection() async {
        let service = FakeCalendarService()
        service.calendarResults = [[makeCalendar("a"), makeCalendar("b")]]
        let store = InMemoryCalendarSelectionStore(.selected(["b"]))

        let manager = CalendarManager(calendarService: service, selectionStore: store)
        await manager.reloadCalendarAndReminderLists()

        XCTAssertEqual(manager.selectedCalendarIDs, ["b"])
        XCTAssertEqual(manager.selectedCalendars.map(\.id), ["b"])
    }

    func testSelectionChangeIsSafeWhenNoManagerExists() async {
        let service = FakeCalendarService()
        service.calendarResults = [[makeCalendar("a")]]
        let store = InMemoryCalendarSelectionStore()
        let provider = CalendarSettingsDataProvider(service: service, selectionStore: store)
        await provider.loadLists()

        provider.setSelected(makeCalendar("a"), isSelected: false)

        XCTAssertEqual(store.selectionState.selectedIdentifiers, [])
        XCTAssertEqual(store.notifyCount, 1)
    }

    func testSelectionChangeUpdatesEventResults() async {
        let service = FakeCalendarService()
        service.calendarResults = [[makeCalendar("a"), makeCalendar("b")]]
        service.eventsHandler = { ids in
            ids.sorted().map { makeEvent(id: "e-\($0)", calendar: $0) }
        }
        let store = InMemoryCalendarSelectionStore(.all)
        let manager = CalendarManager(calendarService: service, selectionStore: store)
        await manager.reloadCalendarAndReminderLists()
        XCTAssertEqual(manager.events.map(\.calendar.id).sorted(), ["a", "b"])

        let provider = CalendarSettingsDataProvider(service: service, selectionStore: store)
        await provider.loadLists()
        provider.setSelected(makeCalendar("a"), isSelected: false)
        await waitUntil { manager.events.map(\.calendar.id) == ["b"] }

        XCTAssertEqual(
            manager.events.map(\.calendar.id),
            ["b"],
            "An actual event refresh must reflect the new selection"
        )
    }

    func testAuthorizationRefreshUpdatesRunningManagerThroughInjectedService() async {
        let service = FakeCalendarService()
        service.statuses = [.event: .denied, .reminder: .denied]
        let store = InMemoryCalendarSelectionStore(.all)
        let manager = CalendarManager(calendarService: service, selectionStore: store)
        await manager.reloadCalendarAndReminderLists()
        manager.refreshCalendarAuthorizationStatus()
        XCTAssertTrue(manager.eventCalendars.isEmpty)
        XCTAssertEqual(manager.calendarAuthorizationStatus, .denied)

        service.statuses = [.event: .fullAccess, .reminder: .denied]
        service.calendarResults = [[makeCalendar("a")]]
        service.eventsHandler = { ids in
            ids.map { makeEvent(id: "e-\($0)", calendar: $0) }
        }

        let provider = CalendarSettingsDataProvider(service: service, selectionStore: store)
        await provider.refreshAfterReturningToApp()
        await waitUntil { manager.eventCalendars.map(\.id) == ["a"] }

        XCTAssertEqual(manager.calendarAuthorizationStatus, .fullAccess)
        XCTAssertEqual(manager.eventCalendars.map(\.id), ["a"])
        XCTAssertEqual(manager.events.map(\.calendar.id), ["a"])
    }

    func testSlowOlderDateLoadCannotOverwriteNewerResults() async {
        let service = GatedFirstEventCalendarService()
        service.calendarsResult = [makeCalendar("a")]
        service.eventsHandler = { start, _ in
            [makeEvent(id: "day", calendar: "a", start: start)]
        }
        let manager = CalendarManager(
            calendarService: service,
            selectionStore: InMemoryCalendarSelectionStore(.all)
        )

        let reload = Task { await manager.reloadCalendarAndReminderLists() }
        await waitUntil { service.eventCallCount >= 1 }

        // A newer date is requested while the first, older date load is still in
        // flight.
        let newerDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        await manager.updateCurrentDate(newerDate)
        let expectedStart = Calendar.current.startOfDay(for: newerDate)
        XCTAssertEqual(manager.events.first?.start, expectedStart)

        service.releaseFirstEventCall()
        await reload.value

        XCTAssertEqual(
            manager.events.first?.start,
            expectedStart,
            "A slower, older date load must not overwrite the newer date's results"
        )
    }

    func testReminderCompletionRefreshesEvents() async {
        let service = FakeCalendarService()
        service.calendarResults = [[makeCalendar("a")]]
        var completed = false
        service.eventsHandler = { ids in
            ids.map { makeEvent(id: completed ? "done" : "open", calendar: $0) }
        }
        service.reminderCompletionHandler = { _, value in completed = value }

        let manager = CalendarManager(
            calendarService: service,
            selectionStore: InMemoryCalendarSelectionStore(.all)
        )
        await manager.reloadCalendarAndReminderLists()
        XCTAssertEqual(manager.events.map(\.id), ["open"])

        await manager.setReminderCompleted(reminderID: "reminder-1", completed: true)

        XCTAssertEqual(
            manager.events.map(\.id),
            ["done"],
            "Completing a reminder must refresh events after the mutation"
        )
    }

    func testSelectionChangeDuringInitialLoadingStillProducesListsAndEvents() async {
        let service = GatedCalendarService()
        service.results = [[makeCalendar("a"), makeCalendar("b")]]
        service.eventsHandler = { ids in
            ids.sorted().map { makeEvent(id: "e-\($0)", calendar: $0) }
        }
        let store = InMemoryCalendarSelectionStore(.all)
        let manager = CalendarManager(calendarService: service, selectionStore: store)

        let reload = Task { await manager.reloadCalendarAndReminderLists() }
        await waitUntil { service.callCount >= 1 }

        // Selection changes while the initial calendar list is still loading.
        store.selectionState = .selected(["b"])
        store.notifySelectionChanged()

        service.releaseFirstCall()
        await reload.value
        await waitUntil { manager.events.map(\.calendar.id) == ["b"] }

        XCTAssertEqual(
            manager.allCalendars.map(\.id).sorted(),
            ["a", "b"],
            "The initial list load must not be discarded by a concurrent selection change"
        )
        XCTAssertEqual(manager.selectedCalendars.map(\.id), ["b"])
        XCTAssertEqual(
            manager.events.map(\.calendar.id),
            ["b"],
            "Events must reflect the selection once the initial list finishes"
        )
    }
}

/// An event source whose first `events` call blocks, so an older date load can be
/// superseded deterministically.
private final class GatedFirstEventCalendarService: CalendarServiceProviding {
    var calendarsResult: [CalendarModel] = []
    var eventsHandler: ((Date, [String]) -> [EventModel])?
    private(set) var eventCallCount = 0
    private var gate: CheckedContinuation<Void, Never>?

    func authorizationStatus(for type: EKEntityType) -> EKAuthorizationStatus { .fullAccess }
    func requestAccess(to type: EKEntityType) async throws -> Bool { true }
    func calendars() async -> [CalendarModel] { calendarsResult }

    func events(from start: Date, to end: Date, calendars: [String]) async -> [EventModel] {
        let index = eventCallCount
        eventCallCount += 1
        if index == 0 {
            await withCheckedContinuation { self.gate = $0 }
        }
        return eventsHandler?(start, calendars) ?? []
    }

    func releaseFirstEventCall() {
        gate?.resume()
        gate = nil
    }
}
