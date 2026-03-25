import SwiftUI
import CalSyncLib

struct AccountView: View {
    @Bindable var appState: AppState
    
    @State private var clientId: String = ""
    @State private var clientSecret: String = ""
    
    var body: some View {
        Form {
            Section("Google API Credentials") {
                TextField("Client ID", text: $clientId)
                SecureField("Client Secret", text: $clientSecret)
                
                Button("Authenticate...") {
                    Task {
                        await appState.authenticate(clientId: clientId, clientSecret: clientSecret)
                    }
                }
                .disabled(clientId.isEmpty || clientSecret.isEmpty)
            }
            
            Section("Status") {
                HStack {
                    Text("Connection:")
                    Spacer()
                    if appState.isAuthenticated {
                        Label("Authenticated", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Label("Not Authenticated", systemImage: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }
                }
            }
            
            if let error = appState.syncError {
                Section("Error") {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            Task {
                await appState.checkAuthStatus()
            }
        }
    }
}
