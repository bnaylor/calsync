import SwiftUI
import SwiftData
import CalSyncLib

struct NewMappingView: View {
    @Bindable var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedIcloudID: String = ""
    @State private var name: String = ""
    @State private var useExistingGoogle = false
    @State private var selectedGoogleID: String = ""
    @State private var isCreating = false

    private var selectedCalendar: iCloudCalendar? {
        appState.availableCalendars.first(where: { $0.id == selectedIcloudID })
    }

    private var canAdd: Bool {
        guard !selectedIcloudID.isEmpty && !name.isEmpty && !isCreating else { return false }
        return useExistingGoogle ? !selectedGoogleID.isEmpty : true
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
                    Text("Mapping Name")
                }

                Section {
                    Toggle("Link to existing Google Calendar", isOn: $useExistingGoogle)
                        .disabled(selectedIcloudID.isEmpty)

                    if useExistingGoogle {
                        if appState.isFetchingGoogleCalendars {
                            ProgressView("Fetching Google Calendars...")
                        } else {
                            Picker("Google Calendar", selection: $selectedGoogleID) {
                                Text("Select a calendar").tag("")
                                ForEach(appState.availableGoogleCalendars.sorted(by: { $0.value < $1.value }), id: \.key) { id, calName in
                                    Text(calName).tag(id)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Google Calendar")
                } footer: {
                    Text(useExistingGoogle
                         ? "Events in the selected Google Calendar will sync to iCloud."
                         : "A new Google Calendar will be created with the mapping name.")
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
                                existingGoogleID: useExistingGoogle ? selectedGoogleID : nil,
                                modelContext: modelContext
                            )
                            isCreating = false
                            dismiss()
                        }
                    }
                    .disabled(!canAdd)
                }
            }
            .onAppear {
                Task {
                    await appState.fetchAvailableCalendars()
                    await appState.fetchGoogleCalendars()
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
