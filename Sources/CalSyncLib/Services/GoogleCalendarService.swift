import Foundation

public actor GoogleCalendarService: GoogleCalendarServiceProtocol {
    private let session = URLSession.shared
    private let authService: GoogleAuthService
    private let baseURL = "https://www.googleapis.com/calendar/v3"

    public enum ServiceError: Error {
        case authenticationRequired
        case apiError(Int, String)
        case invalidURL(String)
    }

    public init(authService: GoogleAuthService = GoogleAuthService()) {
        self.authService = authService
    }

    // MARK: - API Methods

    public func listCalendars() async throws -> [String: String] {
        struct CalendarList: Codable {
            struct Item: Codable { let id: String; let summary: String }
            let items: [Item]?
        }
        let data = try await authenticatedRequest(path: "/users/me/calendarList", method: "GET")
        let list = try JSONDecoder().decode(CalendarList.self, from: data)
        var result: [String: String] = [:]
        for item in list.items ?? [] {
            result[item.id] = item.summary
        }
        return result
    }

    public func createCalendar(name: String) async throws -> String {
        struct CalendarBody: Codable { let summary: String }
        struct CalendarResponse: Codable { let id: String }
        let body = try JSONEncoder().encode(CalendarBody(summary: name))
        let data = try await authenticatedRequest(path: "/calendars", method: "POST", body: body)
        let response = try JSONDecoder().decode(CalendarResponse.self, from: data)
        return response.id
    }

    public func listEvents(calendarID: String, timeMin: Date, timeMax: Date) async throws -> [GoogleEvent] {
        struct EventList: Codable {
            let items: [GoogleEvent]?
        }
        let formatter = ISO8601DateFormatter()
        let encodedCalID = calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID
        var components = URLComponents(string: baseURL + "/calendars/\(encodedCalID)/events")!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: formatter.string(from: timeMin)),
            URLQueryItem(name: "timeMax", value: formatter.string(from: timeMax)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "maxResults", value: "2500"),
        ]
        guard let url = components.url else {
            throw ServiceError.invalidURL(calendarID)
        }
        let data = try await authenticatedRequest(url: url, method: "GET")
        let list = try JSONDecoder().decode(EventList.self, from: data)
        return list.items ?? []
    }

    public func createEvent(calendarID: String, event: GoogleEvent) async throws -> String {
        let encodedCalID = calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID
        let body = try JSONEncoder().encode(event)
        let data = try await authenticatedRequest(path: "/calendars/\(encodedCalID)/events", method: "POST", body: body)
        let created = try JSONDecoder().decode(GoogleEvent.self, from: data)
        return created.id ?? ""
    }

    public func updateEvent(calendarID: String, eventID: String, event: GoogleEvent) async throws {
        let encodedCalID = calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID
        let encodedEventID = eventID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? eventID
        let body = try JSONEncoder().encode(event)
        _ = try await authenticatedRequest(path: "/calendars/\(encodedCalID)/events/\(encodedEventID)", method: "PUT", body: body)
    }

    public func deleteEvent(calendarID: String, eventID: String) async throws {
        let encodedCalID = calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID
        let encodedEventID = eventID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? eventID
        _ = try await authenticatedRequest(path: "/calendars/\(encodedCalID)/events/\(encodedEventID)", method: "DELETE", expectEmpty: true)
    }

    // MARK: - Auth Interceptor

    private func authenticatedRequest(path: String, method: String, body: Data? = nil, expectEmpty: Bool = false) async throws -> Data {
        guard let url = URL(string: baseURL + path) else {
            throw ServiceError.invalidURL(path)
        }
        return try await authenticatedRequest(url: url, method: method, body: body, expectEmpty: expectEmpty)
    }

    private func authenticatedRequest(url: URL, method: String, body: Data? = nil, expectEmpty: Bool = false, isRetry: Bool = false) async throws -> Data {
        let token = try await authService.getValidAccessToken()
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.apiError(0, "No HTTP response")
        }

        // 401 retry with token refresh (once)
        if httpResponse.statusCode == 401 && !isRetry {
            _ = try await authService.refreshAccessToken()
            return try await authenticatedRequest(url: url, method: method, body: body, expectEmpty: expectEmpty, isRetry: true)
        }

        if expectEmpty && httpResponse.statusCode == 204 {
            return Data()
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ServiceError.apiError(httpResponse.statusCode, message)
        }

        return data
    }
}
