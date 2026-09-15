//
//  CalendarSettingsProviderTests.swift
//  NotchKitTests
//

import EventKit
import XCTest
@testable import NotchKit

@MainActor
final class CalendarSettingsProviderTests: XCTestCase {

    func testReadingStatusAndLoadingDoesNotRequestAccess() async {
        let service = FakeCalendarService()
        service.statuses = [.event: .notDetermined, .reminder: .notDetermined]
        service.calendarResults = [[makeCalendar("work")]]
        let provider = CalendarSettingsDataProvider(
            service: service,
            selectionStore: InMemoryCalendarSelectionStore()
        )

        provider.refreshStatuses()
        await provider.loadLists()

        XCTAssertEqual(service.requestCount, 0, "Reading status/loading must not request access")
        XCTAssertEqual(provider.eventCalendars.map(\.id), ["work"])
    }

    func testExplicitGrantRequestsCalendarAccess() async {
        let service = FakeCalendarService()
        service.statuses = [.event: .notDetermined, .reminder: .notDetermined]
        let provider = CalendarSettingsDataProvider(
            service: service,
            selectionStore: InMemoryCalendarSelectionStore()
        )

        await provider.requestEventAccess()

        XCTAssertEqual(service.requestCount, 1)
        XCTAssertEqual(service.requestedTypes, [.event])
        XCTAssertEqual(provider.eventAuthorization, .fullAccess)
    }

    func testExplicitGrantRequestsReminderAccess() async {
        let service = FakeCalendarService()
        service.statuses = [.event: .notDetermined, .reminder: .notDetermined]
        let provider = CalendarSettingsDataProvider(
            service: service,
            selectionStore: InMemoryCalendarSelectionStore()
        )

        await provider.requestReminderAccess()

        XCTAssertEqual(service.requestCount, 1)
        XCTAssertEqual(service.requestedTypes, [.reminder])
        XCTAssertEqual(provider.reminderAuthorization, .fullAccess)
    }

    func testSelectionPersistsThroughTheSharedStoreWithCollapseSemantics() async {
        let service = FakeCalendarService()
        service.calendarResults = [[makeCalendar("a"), makeCalendar("b")]]
        let store = InMemoryCalendarSelectionStore()
        let provider = CalendarSettingsDataProvider(service: service, selectionStore: store)
        await provider.loadLists()

        provider.setSelected(makeCalendar("a"), isSelected: false)

        XCTAssertEqual(store.selectionState.selectedIdentifiers, ["b"])
        XCTAssertEqual(store.notifyCount, 1, "A change must signal the live feature")
        XCTAssertFalse(provider.isSelected(makeCalendar("a")))
        XCTAssertTrue(provider.isSelected(makeCalendar("b")))

        // Re-selecting both collapses back to `.all`.
        provider.setSelected(makeCalendar("a"), isSelected: true)
        XCTAssertNil(store.selectionState.selectedIdentifiers)
    }

    func testAuthorizationRefreshSignalsOnlyOnChange() async {
        let service = FakeCalendarService()
        service.statuses = [.event: .denied, .reminder: .denied]
        let provider = CalendarSettingsDataProvider(
            service: service,
            selectionStore: InMemoryCalendarSelectionStore()
        )
        provider.refreshStatuses()

        var notifications = 0
        let token = NotificationCenter.default.addObserver(
            forName: .calendarAuthorizationChanged,
            object: nil,
            queue: .main
        ) { _ in notifications += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        service.statuses = [.event: .fullAccess, .reminder: .denied]
        await provider.refreshAfterReturningToApp()
        XCTAssertEqual(notifications, 1, "A real change must signal a running feature")

        await provider.refreshAfterReturningToApp()
        XCTAssertEqual(notifications, 1, "No change must not spam refreshes")
    }

    func testSupersededLoadResultsAreDiscarded() async {
        let service = GatedCalendarService()
        service.results = [
            [makeCalendar("stale")],
            [makeCalendar("fresh")],
        ]
        let provider = CalendarSettingsDataProvider(
            service: service,
            selectionStore: InMemoryCalendarSelectionStore()
        )

        let first = Task { await provider.loadLists() }
        await waitUntil { service.callCount >= 1 }

        // Second load supersedes the first while it is still suspended.
        await provider.loadLists()
        XCTAssertEqual(provider.eventCalendars.map(\.id), ["fresh"])

        service.releaseFirstCall()
        await first.value

        XCTAssertEqual(
            provider.eventCalendars.map(\.id),
            ["fresh"],
            "A slower, older load must not overwrite the newer result"
        )
    }

    func testSettingsDoNotInstantiateCalendarManager() async {
        let before = CalendarManager.instanceCount
        let service = FakeCalendarService()
        service.calendarResults = [[makeCalendar("a")]]
        let provider = CalendarSettingsDataProvider(
            service: service,
            selectionStore: InMemoryCalendarSelectionStore()
        )

        provider.refreshStatuses()
        await provider.loadLists()
        provider.setSelected(makeCalendar("a"), isSelected: false)
        await provider.refreshAfterReturningToApp()

        XCTAssertEqual(
            CalendarManager.instanceCount,
            before,
            "The settings page must never instantiate a CalendarManager"
        )
    }
}
