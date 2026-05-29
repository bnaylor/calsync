import SwiftUI
import SwiftData
import CalSyncLib

struct MenuBarView: View {
    @Bindable var appState: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 12) {
            header

            if let error = appState.syncError {
                errorBanner(error)
            }

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
                        .foregroundStyle(.blue)
                } else if let lastSync = appState.lastSuccessfulSync {
                    Text("Last synced: \(lastSync.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not synced yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                Task { await appState.triggerSync() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(appState.isSyncing)
            .buttonStyle(.borderedProminent)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var mappingList: some View {
        MappingListView()
    }

    private var footer: some View {
        HStack {
            Button("Settings...") {
                openSettings()
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

private struct MappingListView: View {
    @Query private var mappings: [CalendarMapping]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CALENDARS (\(mappings.count))")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            if mappings.isEmpty {
                Text("No calendars configured.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(mappings) { mapping in
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundStyle(.blue)
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
}
