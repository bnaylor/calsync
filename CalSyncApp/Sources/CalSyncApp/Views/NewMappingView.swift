import SwiftUI
import SwiftData
import CalSyncLib

struct NewMappingView: View {
    @Bindable var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedIcloudId: String = ""
    @State private var selectedGoogleId: String = ""
    @State private var name: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("iCloud Calendar") {
                    if appState.isFetchingCalendars {
                        ProgressView("Fetching...")
                    } else {
                        Picker("Select Calendar", selection: $selectedIcloudId) {
                            Text("Select a calendar").tag("")
                            ForEach(appState.availableCalendars) { calendar in
                                Text("\(calendar.title) (\(calendar.sourceTitle))").tag(calendar.id)
                            }
                        }
                    }
                }
                
                Section("Google Calendar") {
                    if !appState.isAuthenticated {
                        Text("Please authenticate in Account tab first.")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else if appState.googleCalendars.isEmpty && !appState.isFetchingCalendars {
                        Text("No Google calendars found.")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else {
                        Picker("Select Calendar", selection: $selectedGoogleId) {
                            Text("Select a calendar").tag("")
                            ForEach(appState.googleCalendars.sorted(by: { $0.value < $1.value }), id: \.key) { id, name in
                                Text(name).tag(id)
                            }
                        }
                    }
                }
                
                Section("Mapping Details") {
                    TextField("Name", text: $name)
                }
            }
            .navigationTitle("Add Mapping")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addMapping()
                        dismiss()
                    }
                    .disabled(selectedIcloudId.isEmpty || selectedGoogleId.isEmpty || name.isEmpty)
                }
            }
            .onAppear {
                Task {
                    await appState.fetchAvailableCalendars()
                    if let firstIcloud = appState.availableCalendars.first {
                        selectedIcloudId = firstIcloud.id
                        name = firstIcloud.title
                    }
                }
            }
        }
    }
    
    private func addMapping() {
        let mapping = CalendarMapping(
            icloudIdentifier: selectedIcloudId,
            googleCalendarID: selectedGoogleId,
            name: name
        )
        modelContext.insert(mapping)
        try? modelContext.save()
    }
}
