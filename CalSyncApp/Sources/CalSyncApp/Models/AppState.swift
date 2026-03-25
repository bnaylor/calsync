import SwiftUI
import SwiftData
import CalSyncLib

@Observable
public final class AppState {
    public var isSyncing = false
    public var lastSyncDate: Date?
    public var syncError: String?
    
    // Auth status
    public var isAuthenticated = false
    
    // Calendar fetching
    public var availableCalendars: [iCloudCalendar] = []
    public var googleCalendars: [String: String] = [:] // [id: name]
    public var isFetchingCalendars = false
    
    // Services
    private let authService = GoogleAuthService()
    private let icloudService = iCloudService()
    private let googleService = GoogleCalendarService()
    
    public init() {}
    
    @MainActor
    public func startSync(modelContext: ModelContext) async {
        guard !isSyncing else { return }
        
        isSyncing = true
        syncError = nil
        
        do {
            let engine = SyncEngine(modelContainer: modelContext.container)
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
    
    @MainActor
    public func fetchAvailableCalendars() async {
        isFetchingCalendars = true
        do {
            availableCalendars = try await icloudService.fetchCalendars()
            if isAuthenticated {
                googleCalendars = try await googleService.listCalendars()
            }
        } catch {
            syncError = "Failed to fetch calendars: \(error.localizedDescription)"
        }
        isFetchingCalendars = false
    }
}
