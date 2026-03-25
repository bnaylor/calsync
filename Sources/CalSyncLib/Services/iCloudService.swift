import Foundation
import EventKit

public actor iCloudService {
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
}
