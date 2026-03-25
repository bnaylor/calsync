import SwiftUI
import CalSyncLib

struct SettingsView: View {
    @Bindable var appState: AppState
    
    var body: some View {
        TabView {
            CalendarsView(appState: appState)
                .tabItem {
                    Label("Calendars", systemImage: "calendar")
                }
            
            AccountView(appState: appState)
                .tabItem {
                    Label("Account", systemImage: "person.crop.circle")
                }
        }
        .padding()
    }
}
