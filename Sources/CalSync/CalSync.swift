import Foundation
import ArgumentParser
import SwiftData

@main
struct CalSync: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Syncs private iCloud calendars to Google Calendar.",
        subcommands: [Sync.self, ListCalendars.self, Configure.self, Auth.self]
    )
    
    struct Auth: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Authenticate with Google Calendar.")
        
        @Argument(help: "Google Client ID")
        var clientId: String
        
        @Argument(help: "Google Client Secret")
        var clientSecret: String
        
        func run() async throws {
            let authService = GoogleAuthService(clientId: clientId, clientSecret: clientSecret)
            let token = try await authService.authenticate()
            
            // For now, print it. In the future, save to Keychain.
            print("\nSuccessfully authenticated!")
            print("Access Token: \(token)")
            print("\nNOTE: In a production version, this would be saved securely in the macOS Keychain.")
        }
    }
    
    struct Configure: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Link an iCloud calendar to a Google Calendar.")
        
        @Argument(help: "The iCloud calendar identifier.")
        var icloudID: String
        
        @Argument(help: "The Google Calendar identifier.")
        var googleID: String
        
        @Option(name: .shortAndLong, help: "The name of the mapping.")
        var name: String?
        
        func run() async throws {
            let container = try ModelContainer(for: CalendarMapping.self)
            let context = ModelContext(container)
            
            let mapping = CalendarMapping(
                icloudIdentifier: icloudID,
                googleCalendarID: googleID,
                name: name ?? "New Mapping"
            )
            
            context.insert(mapping)
            try context.save()
            print("Successfully configured mapping: \(name ?? "New Mapping")")
        }
    }
    
    struct Sync: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Run the sync process.")
        
        func run() async throws {
            let container = try ModelContainer(for: EventMapping.self, CalendarMapping.self)
            let engine = SyncEngine(modelContainer: container)
            
            print("Starting sync...")
            try await engine.sync()
            print("Sync complete.")
        }
    }
    
    struct ListCalendars: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List available iCloud calendars.")
        
        func run() async throws {
            let service = iCloudService()
            let calendars = try await service.fetchCalendars()
            
            print("Found \(calendars.count) iCloud calendars:")
            for calendar in calendars {
                print("- \(calendar.title) [\(calendar.sourceTitle)] (Identifier: \(calendar.id))")
            }
        }
    }
}
