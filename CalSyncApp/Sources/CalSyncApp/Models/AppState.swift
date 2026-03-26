import SwiftUI
import SwiftData
import CalSyncLib

@MainActor
@Observable
public final class AppState {
    public var isSyncing = false
    public var lastSyncDate: Date?
    public var syncError: String?

    public var isAuthenticated = false

    public var availableCalendars: [iCloudCalendar] = []
    public var isFetchingCalendars = false

    private let authService: GoogleAuthService
    private let icloudService: iCloudService
    private let googleService: GoogleCalendarService

    public init() {
        let auth = GoogleAuthService()
        self.authService = auth
        self.icloudService = iCloudService()
        self.googleService = GoogleCalendarService(authService: auth)
    }

    public func startSync(modelContext: ModelContext) async {
        guard !isSyncing else { return }

        isSyncing = true
        syncError = nil

        do {
            let engine = SyncEngine(
                modelContainer: modelContext.container,
                icloudService: icloudService,
                googleService: googleService
            )
            try await engine.sync()
            lastSyncDate = .now
        } catch {
            syncError = error.localizedDescription
        }

        isSyncing = false
    }

    public func authenticate(clientId: String, clientSecret: String) async {
        do {
            try await authService.authenticate(clientId: clientId, clientSecret: clientSecret)
            isAuthenticated = true
            syncError = nil
        } catch {
            syncError = "Authentication failed: \(error.localizedDescription)"
            isAuthenticated = false
        }
    }

    public func checkAuthStatus() async {
        do {
            _ = try await authService.getValidAccessToken()
            isAuthenticated = true
        } catch {
            isAuthenticated = false
        }
    }

    public func fetchAvailableCalendars() async {
        isFetchingCalendars = true
        do {
            availableCalendars = try await icloudService.fetchCalendars()
        } catch {
            syncError = "Failed to fetch iCloud calendars: \(error.localizedDescription)"
        }
        isFetchingCalendars = false
    }

    public func addCalendarMapping(icloudCalendar: iCloudCalendar, name: String, modelContext: ModelContext) async {
        do {
            let googleCalendarID = try await googleService.createCalendar(name: name)
            let mapping = CalendarMapping(
                icloudIdentifier: icloudCalendar.id,
                googleCalendarID: googleCalendarID,
                name: name
            )
            modelContext.insert(mapping)
            try modelContext.save()
        } catch {
            syncError = "Failed to create calendar mapping: \(error.localizedDescription)"
        }
    }
}
