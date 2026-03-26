import SwiftUI
import SwiftData
import CalSyncLib

struct NewMappingView: View {
    @Bindable var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedIcloudID: String = ""
    @State private var name: String = ""
    @State private var isCreating = false

    private var selectedCalendar: iCloudCalendar? {
        appState.availableCalendars.first(where: { $0.id == selectedIcloudID })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("iCloud Calendar") {
                    if appState.isFetchingCalendars {
                        ProgressView("Fetching calendars...")
                    } else {
                        Picker("Calendar", selection: $selectedIcloudID) {
                            Text("Select a calendar").tag("")
                            ForEach(appState.availableCalendars) { calendar in
                                Text("\(calendar.title) (\(calendar.sourceTitle))")
                                    .tag(calendar.id)
                            }
                        }
                    }
                }

                Section {
                    TextField("Name", text: $name)
                        .disabled(selectedIcloudID.isEmpty)
                } header: {
                    Text("Google Calendar Name")
                } footer: {
                    Text("A new Google Calendar will be created with this name.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Calendar")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let calendar = selectedCalendar else { return }
                        isCreating = true
                        Task {
                            await appState.addCalendarMapping(
                                icloudCalendar: calendar,
                                name: name,
                                modelContext: modelContext
                            )
                            isCreating = false
                            dismiss()
                        }
                    }
                    .disabled(selectedIcloudID.isEmpty || name.isEmpty || isCreating)
                }
            }
            .onAppear {
                Task {
                    await appState.fetchAvailableCalendars()
                }
            }
            .onChange(of: selectedIcloudID) { _, newValue in
                if let calendar = appState.availableCalendars.first(where: { $0.id == newValue }),
                   name.isEmpty {
                    name = calendar.title
                }
            }
        }
    }
}
