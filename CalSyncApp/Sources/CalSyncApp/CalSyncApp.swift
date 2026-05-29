import SwiftUI
import SwiftData
import CalSyncLib

@main
struct CalSyncApp: App {
    @State private var appState = AppState()

    var sharedModelContainer: ModelContainer = {
        do {
            return try ModelContainerFactory.makeContainer()
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        MenuBarExtra("CalSync", systemImage: appState.syncError != nil ? "calendar.badge.exclamationmark" : "calendar.badge.clock") {
            MenuBarView(appState: appState)
                .modelContainer(sharedModelContainer)
                .task { appState.start(container: sharedModelContainer) }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(appState: appState)
                .modelContainer(sharedModelContainer)
                .frame(width: 500, height: 400)
        }
    }
}
