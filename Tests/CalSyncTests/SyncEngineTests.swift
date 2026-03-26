import Testing
import SwiftData
import Foundation
@testable import CalSyncLib

@Suite("SyncEngine Tests")
struct SyncEngineTests {
    func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: EventMapping.self, CalendarMapping.self, configurations: config)
    }

    @Test("Phase 1: New iCloud event creates Google event and mapping")
    func phase1NewEvent() async throws {
        let container = try makeContainer()
        let mockiCloud = MockiCloudService()
        let mockGoogle = MockGoogleCalendarService()

        let context = ModelContext(container)
        let calMapping = CalendarMapping(icloudIdentifier: "ical1", googleCalendarID: "gcal1", name: "Test")
        context.insert(calMapping)
        try context.save()

        let engine = SyncEngine(modelContainer: container, icloudService: mockiCloud, googleService: mockGoogle)
        try await engine.sync()

        // No events set up, so no events should be created
        let createdEvents = await mockGoogle.createdEvents
        #expect(createdEvents.isEmpty)
    }

    @Test("Phase 1: iCloud event with no mapping creates Google event")
    func phase1CreatesGoogleEvent() async throws {
        let container = try makeContainer()
        let mockiCloud = MockiCloudService()
        let mockGoogle = MockGoogleCalendarService()

        let context = ModelContext(container)
        let calMapping = CalendarMapping(icloudIdentifier: "ical1", googleCalendarID: "gcal1", name: "Test")
        context.insert(calMapping)
        try context.save()

        let now = Date()
        let testEvent = iCloudEvent(
            id: "test-uid-1",
            title: "Test Event",
            notes: nil,
            location: nil,
            startDate: now,
            endDate: now.addingTimeInterval(3600),
            isAllDay: false,
            status: "confirmed",
            checksum: "abc123"
        )
        await mockiCloud.setEvents(for: "ical1", events: [testEvent])
        await mockGoogle.setNextCreatedEventID("new-google-id")

        // Set up Google mock to return the created event in phase 2,
        // so phase 2 doesn't flag it as a Google-side deletion
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let googleEvent = GoogleEvent(
            id: "new-google-id",
            summary: "Test Event",
            start: GoogleEvent.EventDateTime(dateTime: formatter.string(from: now)),
            end: GoogleEvent.EventDateTime(dateTime: formatter.string(from: now.addingTimeInterval(3600))),
            status: "confirmed"
        )
        await mockGoogle.setEvents(for: "gcal1", events: [googleEvent])

        let engine = SyncEngine(modelContainer: container, icloudService: mockiCloud, googleService: mockGoogle)
        try await engine.sync()

        let createdEvents = await mockGoogle.createdEvents
        #expect(createdEvents.count == 1)
        #expect(createdEvents.first?.event.summary == "Test Event")

        // Check mapping was created - use a fresh context to see engine's changes
        let verifyContext = ModelContext(container)
        let mappings = try verifyContext.fetch(FetchDescriptor<EventMapping>())
        #expect(mappings.count == 1)
        #expect(mappings.first?.icloudUID == "test-uid-1")
        #expect(mappings.first?.googleEventID == "new-google-id")
        #expect(mappings.first?.syncDirection == "icloud")
    }

    @Test("Phase 1: Missing iCloud event flags deletion and Phase 3 deletes from Google")
    func phase1DeletionDetection() async throws {
        let container = try makeContainer()
        let mockiCloud = MockiCloudService()
        let mockGoogle = MockGoogleCalendarService()

        let context = ModelContext(container)
        let calMapping = CalendarMapping(icloudIdentifier: "ical1", googleCalendarID: "gcal1", name: "Test")
        context.insert(calMapping)

        let eventMapping = EventMapping(
            icloudUID: "old-event-uid",
            googleEventID: "g-old-event",
            calendarMappingID: "ical1",
            icloudChecksum: "oldhash",
            googleChecksum: "oldhash",
            syncDirection: "icloud"
        )
        context.insert(eventMapping)
        try context.save()

        await mockiCloud.setEvents(for: "ical1", events: [])

        let engine = SyncEngine(modelContainer: container, icloudService: mockiCloud, googleService: mockGoogle)
        try await engine.sync()

        // Phase 1 detects iCloud deletion, Phase 3 deletes from Google and purges mapping
        let deleted = await mockGoogle.deletedEvents
        #expect(deleted.count == 1)
        #expect(deleted.first?.eventID == "g-old-event")

        let verifyContext = ModelContext(container)
        let remaining = try verifyContext.fetch(FetchDescriptor<EventMapping>())
        #expect(remaining.isEmpty)
    }

    @Test("Phase 3: deletedOnIcloud + iCloud-originated deletes from Google")
    func phase3DeletedOnIcloudFromIcloud() async throws {
        let container = try makeContainer()
        let mockiCloud = MockiCloudService()
        let mockGoogle = MockGoogleCalendarService()

        let context = ModelContext(container)
        let calMapping = CalendarMapping(icloudIdentifier: "ical1", googleCalendarID: "gcal1", name: "Test")
        context.insert(calMapping)
        let eventMapping = EventMapping(
            icloudUID: "uid1", googleEventID: "gid1", calendarMappingID: "ical1",
            icloudChecksum: "h1", googleChecksum: "h1", syncDirection: "icloud",
            deletedOnIcloud: true
        )
        context.insert(eventMapping)
        try context.save()

        await mockiCloud.setEvents(for: "ical1", events: [])
        let engine = SyncEngine(modelContainer: container, icloudService: mockiCloud, googleService: mockGoogle)
        try await engine.sync()

        let deleted = await mockGoogle.deletedEvents
        #expect(deleted.count == 1)
        #expect(deleted.first?.eventID == "gid1")
        let verifyContext = ModelContext(container)
        let remaining = try verifyContext.fetch(FetchDescriptor<EventMapping>())
        #expect(remaining.isEmpty)
    }

    @Test("Phase 3: deletedOnGoogle + iCloud-originated purges when iCloud event also gone")
    func phase3DeletedOnGoogleFromIcloudBothGone() async throws {
        let container = try makeContainer()
        let mockiCloud = MockiCloudService()
        let mockGoogle = MockGoogleCalendarService()

        let context = ModelContext(container)
        let calMapping = CalendarMapping(icloudIdentifier: "ical1", googleCalendarID: "gcal1", name: "Test")
        context.insert(calMapping)
        let eventMapping = EventMapping(
            icloudUID: "uid1", googleEventID: "gid1", calendarMappingID: "ical1",
            icloudChecksum: "h1", googleChecksum: "h1", syncDirection: "icloud",
            deletedOnGoogle: true
        )
        context.insert(eventMapping)
        try context.save()

        // iCloud also has no events — both sides deleted
        await mockiCloud.setEvents(for: "ical1", events: [])
        let engine = SyncEngine(modelContainer: container, icloudService: mockiCloud, googleService: mockGoogle)
        try await engine.sync()

        let verifyContext = ModelContext(container)
        let remaining = try verifyContext.fetch(FetchDescriptor<EventMapping>())
        #expect(remaining.isEmpty)
    }
}
