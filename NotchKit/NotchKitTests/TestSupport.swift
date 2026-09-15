//
//  TestSupport.swift
//  NotchKitTests
//
//  Dependency-injected fakes for the settings providers. These never request
//  real TCC permissions, never read the user's calendars, and never touch
//  personal preferences.
//

import AppKit
import EventKit
import XCTest
@testable import NotchKit

// MARK: - Calendar selection store

final class InMemoryCalendarSelectionStore: CalendarSelectionStore {
    var selectionState: CalendarSelectionState
    private(set) var notifyCount = 0
    var postsNotifications = true

    init(_ initial: CalendarSelectionState = .all) {
        self.selectionState = initial
    }

    func notifySelectionChanged() {
        notifyCount += 1
        if postsNotifications {
            NotificationCenter.default.post(name: .calendarSelectionChanged, object: nil)
        }
    }
}

// MARK: - Calendar service

final class FakeCalendarService: CalendarServiceProviding {
    var statuses: [EKEntityType: EKAuthorizationStatus] = [
        .event: .notDetermined,
        .reminder: .notDetermined,
    ]
    var grantOnRequest = true
    private(set) var requestCount = 0
    private(set) var requestedTypes: [EKEntityType] = []

    var calendarResults: [[CalendarModel]] = []
    private(set) var calendarCallCount = 0

    /// Optional deterministic event source keyed by the requested calendar ids.
    var eventsHandler: (([String]) -> [EventModel])?

    func authorizationStatus(for type: EKEntityType) -> EKAuthorizationStatus {
        statuses[type] ?? .notDetermined
    }

    func requestAccess(to type: EKEntityType) async throws -> Bool {
        requestCount += 1
        requestedTypes.append(type)
        if grantOnRequest { statuses[type] = .fullAccess }
        return grantOnRequest
    }

    func calendars() async -> [CalendarModel] {
        let index = calendarCallCount
        calendarCallCount += 1
        guard !calendarResults.isEmpty else { return [] }
        return calendarResults[min(index, calendarResults.count - 1)]
    }

    func events(from start: Date, to end: Date, calendars: [String]) async -> [EventModel] {
        eventsHandler?(calendars) ?? []
    }

    /// Lets a test observe and react to a reminder completion mutation.
    var reminderCompletionHandler: ((String, Bool) -> Void)?

    func setReminderCompleted(reminderID: String, completed: Bool) async {
        reminderCompletionHandler?(reminderID, completed)
    }
}

/// A calendar service whose first `calendars()` call blocks until released, so
/// superseded-load behaviour can be tested deterministically.
final class GatedCalendarService: CalendarServiceProviding {
    var results: [[CalendarModel]] = []
    private(set) var callCount = 0
    private var gate: CheckedContinuation<Void, Never>?

    func authorizationStatus(for type: EKEntityType) -> EKAuthorizationStatus { .fullAccess }
    func requestAccess(to type: EKEntityType) async throws -> Bool { true }

    func calendars() async -> [CalendarModel] {
        let index = callCount
        callCount += 1
        if index == 0 {
            await withCheckedContinuation { self.gate = $0 }
        }
        guard !results.isEmpty else { return [] }
        return results[min(index, results.count - 1)]
    }

    func events(from start: Date, to end: Date, calendars: [String]) async -> [EventModel] {
        eventsHandler?(calendars) ?? []
    }

    var eventsHandler: (([String]) -> [EventModel])?

    func releaseFirstCall() {
        gate?.resume()
        gate = nil
    }
}

// MARK: - Helpers

func makeCalendar(_ id: String, isReminder: Bool = false) -> CalendarModel {
    CalendarModel(
        id: id,
        account: "Test",
        title: id,
        color: .systemBlue,
        isSubscribed: false,
        isReminder: isReminder
    )
}

func makeEvent(id: String, calendar: String, start: Date = Date()) -> EventModel {
    EventModel(
        id: id,
        start: start,
        end: start.addingTimeInterval(3600),
        title: id,
        location: nil,
        notes: nil,
        url: nil,
        isAllDay: false,
        type: .event(.unknown),
        calendar: makeCalendar(calendar),
        participants: [],
        timeZone: nil,
        hasRecurrenceRules: false,
        priority: nil
    )
}

extension CalendarSelectionState {
    var selectedIdentifiers: Set<String>? {
        if case .selected(let identifiers) = self { return identifiers }
        return nil
    }
}

/// Bounded wait for a condition driven by an async observer/task. Unlike a fixed
/// sleep this returns as soon as the condition holds and cannot hang forever.
@MainActor
func waitUntil(
    timeout: TimeInterval = 2,
    _ condition: () -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline {
        await Task.yield()
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
}
