//
//  CalendarManagerPropagationTests.swift
//  NotchKitTests
//
//  Observable behaviour: a selection change made through the settings provider
//  must reach a running CalendarManager, and a manager created later must read
//  the latest persisted selection.
//

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

        // Allow the notification-driven refresh to run on the main actor.
        try? await Task.sleep(for: .milliseconds(150))

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
}
