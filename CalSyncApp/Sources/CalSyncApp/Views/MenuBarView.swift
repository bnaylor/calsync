import SwiftUI
import SwiftData
import CalSyncLib

struct MenuBarView: View {
    @Bindable var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query private var mappings: [CalendarMapping]
    
    var body: some View {
        VStack(spacing: 12) {
            header
            
            Divider()
            
            mappingList
            
            Divider()
            
            footer
        }
        .padding()
        .frame(width: 300)
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("CalSync")
                    .font(.headline)
                if appState.isSyncing {
                    Text("Syncing...")
                        .font(.caption)
                        .foregroundColor(.blue)
                } else if let lastSync = appState.lastSyncDate {
                    Text("Last synced: \(lastSync.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Not synced yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button {
                Task {
                    await appState.startSync(modelContext: modelContext)
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(appState.isSyncing)
            .buttonStyle(.borderedProminent)
        }
    }
    
    private var mappingList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CALENDARS (\(mappings.count))")
                .font(.caption.bold())
                .foregroundColor(.secondary)
            
            if mappings.isEmpty {
                Text("No calendars configured.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(mappings) { mapping in
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(.blue)
                        Text(mapping.name)
                            .lineLimit(1)
                        Spacer()
                        if mapping.isEnabled {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                        }
                    }
                }
            }
        }
    }
    
    private var footer: some View {
        HStack {
            Button("Settings...") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApp.activate(ignoringOtherApps: true)
            }
            
            Spacer()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .buttonStyle(.plain)
        .font(.caption)
    }
}
