import Foundation

public actor GoogleCalendarService: GoogleCalendarServiceProtocol {
    private let session = URLSession.shared
    private var accessToken: String?

    enum ServiceError: Error {
        case authenticationRequired
        case apiError(String)
        case decodingError
    }

    public init() {}

    public func setAccessToken(_ token: String) {
        self.accessToken = token
    }

    public func listCalendars() async throws -> [String: String] {
        // Stub — Task 6 fully implements
        return [:]
    }

    public func createCalendar(name: String) async throws -> String {
        // Stub — Task 6 fully implements
        return ""
    }

    public func listEvents(calendarID: String, timeMin: Date, timeMax: Date) async throws -> [GoogleEvent] {
        // Stub — Task 6 fully implements
        return []
    }

    public func createEvent(calendarID: String, event: GoogleEvent) async throws -> String {
        guard let token = accessToken else { throw ServiceError.authenticationRequired }

        var request = URLRequest(url: URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(calendarID)/events")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(event)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw ServiceError.apiError("Failed to create event: \(String(data: data, encoding: .utf8) ?? "Unknown error")")
        }

        let decoder = JSONDecoder()
        let createdEvent = try decoder.decode(GoogleEvent.self, from: data)

        return createdEvent.id ?? ""
    }

    public func updateEvent(calendarID: String, eventID: String, event: GoogleEvent) async throws {
        guard let token = accessToken else { throw ServiceError.authenticationRequired }

        var request = URLRequest(url: URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(calendarID)/events/\(eventID)")!)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(event)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw ServiceError.apiError("Failed to update event: \(String(data: data, encoding: .utf8) ?? "Unknown error")")
        }
    }

    public func deleteEvent(calendarID: String, eventID: String) async throws {
        guard let token = accessToken else { throw ServiceError.authenticationRequired }

        var request = URLRequest(url: URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(calendarID)/events/\(eventID)")!)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) && httpResponse.statusCode != 204 else {
            // 204 No Content is success for DELETE
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 204 { return }
            throw ServiceError.apiError("Failed to delete event: \(String(data: data, encoding: .utf8) ?? "Unknown error")")
        }
    }
}
