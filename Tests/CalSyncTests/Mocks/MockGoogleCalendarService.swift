import Foundation
@testable import CalSyncLib

actor MockGoogleCalendarService: GoogleCalendarServiceProtocol {
    var calendars: [String: String] = [:]
    var events: [String: [GoogleEvent]] = [:]
    var createdEvents: [(calendarID: String, event: GoogleEvent)] = []
    var updatedEvents: [(calendarID: String, eventID: String)] = []
    var deletedEvents: [(calendarID: String, eventID: String)] = []
    var nextCreatedEventID: String = "mock-google-\(UUID().uuidString)"

    func listCalendars() async throws -> [String: String] { calendars }
    func createCalendar(name: String) async throws -> String { let id = "mock-cal-\(UUID().uuidString)"; calendars[id] = name; return id }
    func listEvents(calendarID: String, timeMin: Date, timeMax: Date) async throws -> [GoogleEvent] { events[calendarID] ?? [] }
    func createEvent(calendarID: String, event: GoogleEvent) async throws -> String { createdEvents.append((calendarID: calendarID, event: event)); return nextCreatedEventID }
    func updateEvent(calendarID: String, eventID: String, event: GoogleEvent) async throws { updatedEvents.append((calendarID: calendarID, eventID: eventID)) }
    func deleteEvent(calendarID: String, eventID: String) async throws { deletedEvents.append((calendarID: calendarID, eventID: eventID)) }
    func setEvents(for calendarID: String, events: [GoogleEvent]) { self.events[calendarID] = events }
    func setNextCreatedEventID(_ id: String) { self.nextCreatedEventID = id }
}
