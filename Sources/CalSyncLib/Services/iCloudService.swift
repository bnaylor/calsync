import Foundation
import EventKit

public actor iCloudService: iCloudServiceProtocol {
    private let eventStore = EKEventStore()
    
    public enum ServiceError: Error {
        case accessDenied
        case fetchFailed(String)
    }
    
    public init() {}

    public func requestAccess() async throws {
        let granted: Bool
        if #available(macOS 14.0, *) {
            granted = try await eventStore.requestFullAccessToEvents()
        } else {
            granted = try await eventStore.requestAccess(to: .event)
        }
        
        guard granted else {
            throw ServiceError.accessDenied
        }
    }
    
    public func fetchCalendars() async throws -> [iCloudCalendar] {
        try await requestAccess()
        return eventStore.calendars(for: .event)
            .filter { $0.type == .calDAV || $0.type == .subscription }
            .map { iCloudCalendar(from: $0) }
    }
    
    public func fetchEvents(from calendarID: String, startDate: Date, endDate: Date) async throws -> [iCloudEvent] {
        guard let calendar = eventStore.calendar(withIdentifier: calendarID) else {
            throw ServiceError.fetchFailed("Calendar not found: \(calendarID)")
        }
        
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: [calendar])
        return eventStore.events(matching: predicate)
            .compactMap { iCloudEvent(from: $0) }
    }

    public func createEvent(in calendarID: String, title: String, notes: String?, location: String?, startDate: Date, endDate: Date, isAllDay: Bool) async throws -> String {
        guard let calendar = eventStore.calendar(withIdentifier: calendarID) else {
            throw ServiceError.fetchFailed("Calendar not found: \(calendarID)")
        }
        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = title
        event.notes = notes
        event.location = location
        event.startDate = startDate
        event.endDate = endDate
        event.isAllDay = isAllDay
        try eventStore.save(event, span: .thisEvent)
        return event.calendarItemExternalIdentifier
    }

    public func updateEvent(identifier: String, title: String, notes: String?, location: String?, startDate: Date, endDate: Date, isAllDay: Bool) async throws {
        guard let event = eventStore.calendarItem(withIdentifier: identifier) as? EKEvent else {
            throw ServiceError.fetchFailed("Event not found: \(identifier)")
        }
        event.title = title; event.notes = notes; event.location = location
        event.startDate = startDate; event.endDate = endDate; event.isAllDay = isAllDay
        try eventStore.save(event, span: .thisEvent)
    }

    public func deleteEvent(identifier: String) async throws {
        guard let event = eventStore.calendarItem(withIdentifier: identifier) as? EKEvent else {
            throw ServiceError.fetchFailed("Event not found: \(identifier)")
        }
        try eventStore.remove(event, span: .thisEvent)
    }
}
