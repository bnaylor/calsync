import Foundation
@testable import CalSyncLib

actor MockiCloudService: iCloudServiceProtocol {
    var calendars: [iCloudCalendar] = []
    var events: [String: [iCloudEvent]] = [:]
    var createdEvents: [(calendarID: String, title: String)] = []
    var updatedEvents: [String] = []
    var deletedEvents: [String] = []

    func requestAccess() async throws {}
    func fetchCalendars() async throws -> [iCloudCalendar] { calendars }
    func fetchEvents(from calendarID: String, startDate: Date, endDate: Date) async throws -> [iCloudEvent] { events[calendarID] ?? [] }
    func createEvent(in calendarID: String, title: String, notes: String?, location: String?, startDate: Date, endDate: Date, isAllDay: Bool) async throws -> String {
        createdEvents.append((calendarID: calendarID, title: title))
        return "mock-icloud-\(UUID().uuidString)"
    }
    func updateEvent(identifier: String, title: String, notes: String?, location: String?, startDate: Date, endDate: Date, isAllDay: Bool) async throws { updatedEvents.append(identifier) }
    func deleteEvent(identifier: String) async throws { deletedEvents.append(identifier) }
    func setEvents(for calendarID: String, events: [iCloudEvent]) { self.events[calendarID] = events }
}
