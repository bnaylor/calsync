import Foundation

public protocol iCloudServiceProtocol: Sendable {
    func requestAccess() async throws
    func fetchCalendars() async throws -> [iCloudCalendar]
    func fetchEvents(from calendarID: String, startDate: Date, endDate: Date) async throws -> [iCloudEvent]
    func createEvent(in calendarID: String, title: String, notes: String?, location: String?, startDate: Date, endDate: Date, isAllDay: Bool) async throws -> String
    func updateEvent(identifier: String, title: String, notes: String?, location: String?, startDate: Date, endDate: Date, isAllDay: Bool) async throws
    func deleteEvent(identifier: String) async throws
}

public struct GoogleEvent: Codable, Sendable {
    public var id: String?
    public var summary: String
    public var description: String?
    public var location: String?
    public var start: EventDateTime
    public var end: EventDateTime
    public var status: String?

    public struct EventDateTime: Codable, Sendable {
        public var dateTime: String?
        public var date: String?
        public var timeZone: String?
        public init(dateTime: String? = nil, date: String? = nil, timeZone: String? = nil) {
            self.dateTime = dateTime; self.date = date; self.timeZone = timeZone
        }
    }

    public init(id: String? = nil, summary: String, description: String? = nil, location: String? = nil, start: EventDateTime, end: EventDateTime, status: String? = nil) {
        self.id = id; self.summary = summary; self.description = description; self.location = location; self.start = start; self.end = end; self.status = status
    }

    public var checksum: String {
        let isAllDay = start.date != nil
        let startD: Date
        let endD: Date
        if isAllDay {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            df.timeZone = TimeZone(identifier: "UTC")
            startD = df.date(from: start.date ?? "") ?? Date.distantPast
            endD = df.date(from: end.date ?? "") ?? Date.distantPast
        } else {
            let isoFormatter = ISO8601DateFormatter()
            startD = isoFormatter.date(from: start.dateTime ?? "") ?? Date.distantPast
            endD = isoFormatter.date(from: end.dateTime ?? "") ?? Date.distantPast
        }
        return Checksum.compute(title: summary, description: description, location: location,
            startDate: startD, endDate: endD, isAllDay: isAllDay, status: status ?? "confirmed")
    }
}

public protocol GoogleCalendarServiceProtocol: Sendable {
    func listCalendars() async throws -> [String: String]
    func createCalendar(name: String) async throws -> String
    func listEvents(calendarID: String, timeMin: Date, timeMax: Date) async throws -> [GoogleEvent]
    func createEvent(calendarID: String, event: GoogleEvent) async throws -> String
    func updateEvent(calendarID: String, eventID: String, event: GoogleEvent) async throws
    func deleteEvent(calendarID: String, eventID: String) async throws
}
