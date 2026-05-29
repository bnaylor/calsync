import SwiftUI
import SwiftData
import CalSyncLib
import UserNotifications

@MainActor
@Observable
public final class AppState {
    public var isSyncing = false
    public var syncError: String?
    public var isAuthenticated = false

    public var availableCalendars: [iCloudCalendar] = []
    public var isFetchingCalendars = false
    public var availableGoogleCalendars: [String: String] = [:]
    public var isFetchingGoogleCalendars = false

    // Persisted across launches
    public var lastSuccessfulSync: Date? {
        didSet { UserDefaults.standard.set(lastSuccessfulSync, forKey: "lastSuccessfulSync") }
    }
    public var syncIntervalMinutes: Int {
        didSet { UserDefaults.standard.set(syncIntervalMinutes, forKey: "syncIntervalMinutes") }
    }
    public var staleThresholdHours: Int {
        didSet { UserDefaults.standard.set(staleThresholdHours, forKey: "staleThresholdHours") }
    }

    private var lastNotificationSent: Date? {
        get { UserDefaults.standard.object(forKey: "lastNotificationSent") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastNotificationSent") }
    }

    @ObservationIgnored private var modelContainer: ModelContainer?
    @ObservationIgnored private var syncLoopTask: Task<Void, Never>?

    private let authService: GoogleAuthService
    private let icloudService: iCloudService
    private let googleService: GoogleCalendarService

    public init() {
        let auth = GoogleAuthService()
        self.authService = auth
        self.icloudService = iCloudService()
        self.googleService = GoogleCalendarService(authService: auth)

        let storedInterval = UserDefaults.standard.integer(forKey: "syncIntervalMinutes")
        self.syncIntervalMinutes = storedInterval > 0 ? storedInterval : 10
        let storedThreshold = UserDefaults.standard.integer(forKey: "staleThresholdHours")
        self.staleThresholdHours = storedThreshold > 0 ? storedThreshold : 4
        self.lastSuccessfulSync = UserDefaults.standard.object(forKey: "lastSuccessfulSync") as? Date
    }

    // Called once from the first view appear — idempotent
    public func start(container: ModelContainer) {
        guard modelContainer == nil else { return }
        modelContainer = container
        Task { await checkAuthStatus() }
        requestNotificationPermission()
        startSyncLoop()
    }

    // MARK: - Sync Loop

    private func startSyncLoop() {
        syncLoopTask?.cancel()
        syncLoopTask = Task {
            while !Task.isCancelled {
                await triggerSync()
                try? await Task.sleep(for: .seconds(Double(syncIntervalMinutes) * 60))
            }
        }
    }

    public func triggerSync() async {
        guard let container = modelContainer, !isSyncing else { return }
        isSyncing = true
        syncError = nil
        do {
            let engine = SyncEngine(
                modelContainer: container,
                icloudService: icloudService,
                googleService: googleService
            )
            try await engine.sync()
            lastSuccessfulSync = .now
        } catch {
            syncError = error.localizedDescription
        }
        isSyncing = false
        checkAndSendStalenessNotification()
    }

    // MARK: - Staleness Notification

    private func checkAndSendStalenessNotification() {
        // Only notify if there's been at least one successful sync — don't spam on fresh installs
        guard let lastSuccess = lastSuccessfulSync else { return }

        let stale = Date().timeIntervalSince(lastSuccess) > Double(staleThresholdHours) * 3600
        guard stale else { return }

        let cooldown: TimeInterval = 24 * 3600
        if let last = lastNotificationSent, Date().timeIntervalSince(last) < cooldown { return }

        let content = UNMutableNotificationContent()
        content.title = "CalSync — Sync Overdue"
        let hours = Int(Date().timeIntervalSince(lastSuccess) / 3600)
        content.body = "Last successful sync was \(hours) hour\(hours == 1 ? "" : "s") ago."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "com.calsync.stale",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
        lastNotificationSent = .now
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Auth

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

    // MARK: - Calendars

    public func fetchAvailableCalendars() async {
        isFetchingCalendars = true
        do {
            availableCalendars = try await icloudService.fetchCalendars()
        } catch {
            syncError = "Failed to fetch iCloud calendars: \(error.localizedDescription)"
        }
        isFetchingCalendars = false
    }

    public func fetchGoogleCalendars() async {
        isFetchingGoogleCalendars = true
        do {
            availableGoogleCalendars = try await googleService.listCalendars()
        } catch {
            syncError = "Failed to fetch Google Calendars: \(error.localizedDescription)"
        }
        isFetchingGoogleCalendars = false
    }

    public func addCalendarMapping(icloudCalendar: iCloudCalendar, name: String, existingGoogleID: String? = nil, modelContext: ModelContext) async {
        do {
            let googleCalendarID: String
            if let existingID = existingGoogleID {
                googleCalendarID = existingID
            } else {
                googleCalendarID = try await googleService.createCalendar(name: name)
            }
            let mapping = CalendarMapping(
                icloudIdentifier: icloudCalendar.id,
                googleCalendarID: googleCalendarID,
                name: name
            )
            modelContext.insert(mapping)
            try modelContext.save()
        } catch {
            syncError = "Failed to add calendar mapping: \(error.localizedDescription)"
        }
    }
}
