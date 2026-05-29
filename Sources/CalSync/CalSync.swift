import Foundation
import ArgumentParser
import SwiftData
import CalSyncLib

@main
struct CalSync: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Syncs private iCloud calendars to Google Calendar.",
        subcommands: [Sync.self, ListCalendars.self, ListGoogleCalendars.self, Configure.self, Remove.self, Auth.self, Status.self, Install.self, Uninstall.self]
    )

    struct Auth: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Authenticate with Google Calendar.")

        @Argument(help: "Google Client ID")
        var clientId: String

        @Argument(help: "Google Client Secret")
        var clientSecret: String

        func run() async throws {
            let authService = GoogleAuthService()
            try await authService.authenticate(clientId: clientId, clientSecret: clientSecret)
        }
    }

    struct Configure: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Link an iCloud calendar to a Google Calendar.")

        @Argument(help: "The iCloud calendar identifier.")
        var icloudID: String

        @Option(name: .shortAndLong, help: "The name for this mapping (defaults to iCloud calendar name).")
        var name: String?

        @Option(name: .long, help: "Link to an existing Google Calendar by ID instead of creating a new one.")
        var googleID: String?

        @Option(name: .long, help: "Days to look back (default: 7).")
        var past: Int = 7

        @Option(name: .long, help: "Days to look ahead (default: 30).")
        var future: Int = 30

        func run() async throws {
            let icloud = iCloudService()
            let calendars = try await icloud.fetchCalendars()
            guard let calendar = calendars.first(where: { $0.id == icloudID }) else {
                print("Error: iCloud calendar '\(icloudID)' not found.")
                print("Run 'calsync list-calendars' to see available calendars.")
                return
            }

            let authService = GoogleAuthService()
            let googleService = GoogleCalendarService(authService: authService)
            let calendarName = name ?? calendar.title

            let googleCalendarID: String
            if let existingID = googleID {
                googleCalendarID = existingID
                print("Linking to existing Google Calendar: \(googleCalendarID)")
            } else {
                print("Creating Google Calendar: \(calendarName)...")
                googleCalendarID = try await googleService.createCalendar(name: calendarName)
            }

            let container = try ModelContainerFactory.makeContainer()
            let context = ModelContext(container)
            let mapping = CalendarMapping(
                icloudIdentifier: icloudID,
                googleCalendarID: googleCalendarID,
                name: calendarName,
                syncWindowPast: past,
                syncWindowFuture: future
            )
            context.insert(mapping)
            try context.save()

            print("Successfully configured:")
            print("  iCloud: \(calendar.title) [\(calendar.sourceTitle)]")
            print("  Google: \(calendarName) (\(googleCalendarID))")
            print("  Window: -\(past) to +\(future) days")
        }
    }

    struct Sync: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Run the sync process.")

        func run() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let authService = GoogleAuthService()
            let googleService = GoogleCalendarService(authService: authService)
            let engine = SyncEngine(
                modelContainer: container,
                icloudService: iCloudService(),
                googleService: googleService
            )

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

    struct ListGoogleCalendars: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List available Google Calendars.")

        func run() async throws {
            let authService = GoogleAuthService()
            let googleService = GoogleCalendarService(authService: authService)
            let calendars = try await googleService.listCalendars()

            print("Found \(calendars.count) Google Calendars:")
            for (id, name) in calendars.sorted(by: { $0.value < $1.value }) {
                print("- \(name) (ID: \(id))")
            }
        }
    }

    struct Remove: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Remove a configured calendar mapping.")

        @Argument(help: "The iCloud calendar identifier to remove.")
        var icloudID: String

        @Flag(name: .long, help: "Skip confirmation prompt.")
        var yes: Bool = false

        func run() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = ModelContext(container)
            let id = icloudID
            let mappings = try context.fetch(FetchDescriptor<CalendarMapping>(predicate: #Predicate { $0.icloudIdentifier == id }))

            guard let mapping = mappings.first else {
                print("No mapping found for iCloud ID '\(icloudID)'.")
                print("Run 'calsync status' to see configured calendars.")
                return
            }

            if !yes {
                print("Remove mapping '\(mapping.name)' (\(icloudID))? [y/N] ", terminator: "")
                guard let input = readLine(), input.lowercased() == "y" else {
                    print("Aborted.")
                    return
                }
            }

            let eventDescriptor = FetchDescriptor<EventMapping>(predicate: #Predicate { $0.calendarMappingID == id })
            let events = try context.fetch(eventDescriptor)
            for event in events { context.delete(event) }
            context.delete(mapping)
            try context.save()

            print("Removed '\(mapping.name)' and \(events.count) event mapping(s).")
        }
    }

    struct Status: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show sync status for configured calendars.")

        func run() async throws {
            let container = try ModelContainerFactory.makeContainer()
            let context = ModelContext(container)
            let mappings = try context.fetch(FetchDescriptor<CalendarMapping>())

            if mappings.isEmpty {
                print("No calendars configured. Run 'calsync configure' first.")
                return
            }

            for mapping in mappings {
                let calID = mapping.icloudIdentifier
                let eventDescriptor = FetchDescriptor<EventMapping>(predicate: #Predicate {
                    $0.calendarMappingID == calID
                })
                let events = try context.fetch(eventDescriptor)
                let lastSync = events.map({ $0.lastSyncDate }).max()

                let status = mapping.isEnabled ? "enabled" : "disabled"
                print("\(mapping.name) [\(status)]")
                print("  iCloud ID: \(mapping.icloudIdentifier)")
                print("  Google ID: \(mapping.googleCalendarID ?? "not set")")
                print("  Window: -\(mapping.syncWindowPast) to +\(mapping.syncWindowFuture) days")
                print("  Events tracked: \(events.count)")
                if let lastSync {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    formatter.timeStyle = .short
                    print("  Last sync: \(formatter.string(from: lastSync))")
                } else {
                    print("  Last sync: never")
                }
                print()
            }
        }
    }

    struct Install: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Set up automatic sync via launchd.")

        @Option(name: .long, help: "Sync interval in minutes (default: 10).")
        var interval: Int = 10

        func run() async throws {
            let plistPath = NSHomeDirectory() + "/Library/LaunchAgents/com.calsync.agent.plist"
            let logPath = NSHomeDirectory() + "/Library/Logs/calsync.log"
            let binaryPath = ProcessInfo.processInfo.arguments[0]

            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>com.calsync.agent</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(binaryPath)</string>
                    <string>sync</string>
                </array>
                <key>StartInterval</key>
                <integer>\(interval * 60)</integer>
                <key>StandardOutPath</key>
                <string>\(logPath)</string>
                <key>StandardErrorPath</key>
                <string>\(logPath)</string>
                <key>RunAtLoad</key>
                <true/>
            </dict>
            </plist>
            """

            try plist.write(toFile: plistPath, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["load", plistPath]
            try process.run()
            process.waitUntilExit()

            print("Installed launchd agent: \(plistPath)")
            print("Sync will run every \(interval) minutes.")
            print("Logs: \(logPath)")
        }
    }

    struct Uninstall: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Remove automatic sync scheduling.")

        func run() async throws {
            let plistPath = NSHomeDirectory() + "/Library/LaunchAgents/com.calsync.agent.plist"

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["unload", plistPath]
            try process.run()
            process.waitUntilExit()

            try FileManager.default.removeItem(atPath: plistPath)
            print("Removed launchd agent.")
        }
    }
}
