import SwiftUI
import CalSyncLib

struct SyncSettingsView: View {
    @Bindable var appState: AppState

    var body: some View {
        Form {
            Section {
                Stepper("Every \(appState.syncIntervalMinutes) minute\(appState.syncIntervalMinutes == 1 ? "" : "s")",
                        value: $appState.syncIntervalMinutes, in: 1...60)
            } header: {
                Text("Sync Interval")
            } footer: {
                Text("How often the app syncs in the background.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Stepper("\(appState.staleThresholdHours) hour\(appState.staleThresholdHours == 1 ? "" : "s")",
                        value: $appState.staleThresholdHours, in: 1...24)
            } header: {
                Text("Overdue Notification Threshold")
            } footer: {
                Text("Send a notification if the sync hasn't completed within this time. At most once per day.")
                    .foregroundStyle(.secondary)
            }

            Section("Last Sync") {
                HStack {
                    Text("Successful sync:")
                    Spacer()
                    if let last = appState.lastSuccessfulSync {
                        Text(last.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Never")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
