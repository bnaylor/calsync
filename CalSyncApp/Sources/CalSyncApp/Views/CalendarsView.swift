import SwiftUI
import SwiftData
import CalSyncLib

struct CalendarsView: View {
    @Bindable var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query private var mappings: [CalendarMapping]
    
    @State private var showingNewMapping = false
    
    var body: some View {
        VStack {
            List {
                if mappings.isEmpty {
                    ContentUnavailableView("No Mappings", systemImage: "calendar.badge.plus", description: Text("Add a calendar mapping to start syncing."))
                } else {
                    ForEach(mappings) { mapping in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(mapping.name)
                                    .font(.headline)
                                Text("iCloud ID: \(mapping.icloudIdentifier)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let googleId = mapping.googleCalendarID {
                                    Text("Google ID: \(googleId)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            let bindable = Bindable(mapping)
                            Toggle("", isOn: bindable.isEnabled)
                                .toggleStyle(.switch)
                        }
                        .padding(.vertical, 4)
                        .swipeActions {
                            Button(role: .destructive) {
                                modelContext.delete(mapping)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            
            Button {
                showingNewMapping = true
            } label: {
                Label("Add Mapping...", systemImage: "plus")
            }
            .padding()
        }
        .sheet(isPresented: $showingNewMapping) {
            NewMappingView(appState: appState)
                .modelContainer(modelContext.container)
                .frame(width: 400, height: 300)
        }
    }
}
