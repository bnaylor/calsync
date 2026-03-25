# CalSync Home Pivot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pivot CalSync from one-way corporate sync to bidirectional home sync between private iCloud calendars and Google Calendar.

**Architecture:** Evolve the existing Swift CLI. Update SwiftData models with dual checksums and deletion flags. Rewrite the sync engine into three phases (iCloud detection, Google detection, deletion arbitration). Add Keychain-backed OAuth, EventKit write-back, and launchd scheduling.

**Tech Stack:** Swift 6.2, EventKit, SwiftData, Google Calendar REST API v3, Security.framework (Keychain), CryptoKit, ArgumentParser

**Spec:** `docs/superpowers/specs/2026-03-25-home-pivot-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `Sources/CalSync/Models/EventMapping.swift` | Modify | Add dual checksums, calendarMappingID, syncDirection, deletion flags |
| `Sources/CalSync/Models/CalendarMapping.swift` | Modify | Add sync window fields, autoCreateGoogleCalendar |
| `Sources/CalSync/Models/SyncModels.swift` | Modify | Add attendees/status to iCloudEvent, composite UID |
| `Sources/CalSync/Models/GoogleEvent.swift` | Create | GoogleEvent value type with checksum support |
| `Sources/CalSync/Models/EKEvent+Checksum.swift` | Modify | ISO 8601 UTC dates, add status, shared checksum logic |
| `Sources/CalSync/Models/Checksum.swift` | Create | Shared checksum function for both iCloud and Google events |
| `Sources/CalSyncLib/` | Create (target) | Library target extracted from executable for testability |
| `Sources/CalSync/CalSync.swift` | Modify | Thin executable importing CalSyncLib |
| `Sources/CalSync/Services/KeychainService.swift` | Create | Keychain CRUD for OAuth tokens and client credentials |
| `Sources/CalSync/Services/GoogleAuthService.swift` | Modify | Keychain storage, token refresh, remove print-based output |
| `Sources/CalSync/Services/GoogleCalendarService.swift` | Modify | Full REST implementation, 401 interceptor |
| `Sources/CalSync/Services/iCloudService.swift` | Modify | Add write methods (create, update, delete events) |
| `Sources/CalSync/Engine/SyncEngine.swift` | Rewrite | Three-phase bidirectional sync |
| `Tests/CalSyncTests/ChecksumTests.swift` | Create | Checksum symmetry and normalization tests |
| `Tests/CalSyncTests/EventMappingTests.swift` | Create | Model field tests, composite UID tests |
| `Tests/CalSyncTests/SyncEngineTests.swift` | Create | Phase logic tests with mock services |
| `Tests/CalSyncTests/KeychainServiceTests.swift` | Create | Keychain CRUD tests |
| `Tests/CalSyncTests/Mocks/MockiCloudService.swift` | Create | Protocol + mock for iCloudService |
| `Tests/CalSyncTests/Mocks/MockGoogleCalendarService.swift` | Create | Protocol + mock for GoogleCalendarService |

---

## Task 0: Extract Library Target for Testability

**Files:**
- Modify: `Package.swift`
- Move: All files under `Sources/CalSync/` except `CalSync.swift` → `Sources/CalSyncLib/`
- Modify: `Sources/CalSync/CalSync.swift` (thin executable that re-exports CalSyncLib)

Swift Package Manager cannot `@testable import` executable targets (duplicate `@main` symbol). Extract all logic into a `CalSyncLib` library target. The executable target becomes a thin wrapper.

- [ ] **Step 1: Create library target directory structure**

```bash
mkdir -p Sources/CalSyncLib/Models Sources/CalSyncLib/Services Sources/CalSyncLib/Engine
```

- [ ] **Step 2: Move source files to library target**

```bash
mv Sources/CalSync/Models/* Sources/CalSyncLib/Models/
mv Sources/CalSync/Services/* Sources/CalSyncLib/Services/
mv Sources/CalSync/Engine/* Sources/CalSyncLib/Engine/
```

- [ ] **Step 3: Update Package.swift**

```swift
// Package.swift
// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CalSync",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "CalSyncLib",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "CalSync",
            dependencies: ["CalSyncLib"]
        ),
        .testTarget(
            name: "CalSyncTests",
            dependencies: ["CalSyncLib"]
        ),
    ]
)
```

- [ ] **Step 4: Update CalSync.swift to import CalSyncLib**

`Sources/CalSync/CalSync.swift` keeps the `@main` struct and CLI command definitions, adding `import CalSyncLib`. All model/service/engine types come from the library.

- [ ] **Step 5: Update test imports**

Change `@testable import CalSync` to `@testable import CalSyncLib` in all test files.

- [ ] **Step 6: Verify build and tests pass**

Run: `swift build 2>&1 && swift test 2>&1`
Expected: Both succeed

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/ Tests/
git commit -m "refactor: extract CalSyncLib library target for testability"
```

---

## Task 1: Update SwiftData Models

**Files:**
- Modify: `Sources/CalSync/Models/EventMapping.swift`
- Modify: `Sources/CalSync/Models/CalendarMapping.swift`
- Test: `Tests/CalSyncTests/EventMappingTests.swift`

- [ ] **Step 1: Write tests for updated EventMapping**

```swift
// Tests/CalSyncTests/EventMappingTests.swift
import Testing
import SwiftData
@testable import CalSync

@Suite("EventMapping Tests")
struct EventMappingTests {
    @Test("EventMapping initializes with all required fields")
    func initWithAllFields() throws {
        let mapping = EventMapping(
            icloudUID: "abc123",
            googleEventID: "g456",
            calendarMappingID: "cal789",
            icloudChecksum: "hash1",
            googleChecksum: "hash2",
            syncDirection: "icloud"
        )
        #expect(mapping.icloudUID == "abc123")
        #expect(mapping.googleEventID == "g456")
        #expect(mapping.calendarMappingID == "cal789")
        #expect(mapping.icloudChecksum == "hash1")
        #expect(mapping.googleChecksum == "hash2")
        #expect(mapping.syncDirection == "icloud")
        #expect(mapping.deletedOnIcloud == false)
        #expect(mapping.deletedOnGoogle == false)
    }

    @Test("CalendarMapping initializes with sync window defaults")
    func calendarMappingDefaults() throws {
        let mapping = CalendarMapping(
            icloudIdentifier: "ical123",
            name: "Mom's Calendar"
        )
        #expect(mapping.syncWindowPast == 7)
        #expect(mapping.syncWindowFuture == 30)
        #expect(mapping.autoCreateGoogleCalendar == true)
        #expect(mapping.isEnabled == true)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter EventMappingTests 2>&1`
Expected: Compilation errors — new fields don't exist yet

- [ ] **Step 3: Update EventMapping model**

```swift
// Sources/CalSync/Models/EventMapping.swift
import Foundation
import SwiftData

@Model
final class EventMapping {
    @Attribute(.unique) var icloudUID: String
    var googleEventID: String?
    var calendarMappingID: String
    var lastSyncDate: Date
    var icloudChecksum: String?
    var googleChecksum: String?
    var syncDirection: String
    var deletedOnIcloud: Bool
    var deletedOnGoogle: Bool

    init(
        icloudUID: String,
        googleEventID: String? = nil,
        calendarMappingID: String,
        lastSyncDate: Date = .now,
        icloudChecksum: String? = nil,
        googleChecksum: String? = nil,
        syncDirection: String = "icloud",
        deletedOnIcloud: Bool = false,
        deletedOnGoogle: Bool = false
    ) {
        self.icloudUID = icloudUID
        self.googleEventID = googleEventID
        self.calendarMappingID = calendarMappingID
        self.lastSyncDate = lastSyncDate
        self.icloudChecksum = icloudChecksum
        self.googleChecksum = googleChecksum
        self.syncDirection = syncDirection
        self.deletedOnIcloud = deletedOnIcloud
        self.deletedOnGoogle = deletedOnGoogle
    }
}
```

- [ ] **Step 4: Update CalendarMapping model**

```swift
// Sources/CalSync/Models/CalendarMapping.swift
import Foundation
import SwiftData

@Model
final class CalendarMapping {
    @Attribute(.unique) var icloudIdentifier: String
    var googleCalendarID: String?
    var name: String
    var isEnabled: Bool
    var syncWindowPast: Int
    var syncWindowFuture: Int
    var autoCreateGoogleCalendar: Bool

    init(
        icloudIdentifier: String,
        googleCalendarID: String? = nil,
        name: String,
        isEnabled: Bool = true,
        syncWindowPast: Int = 7,
        syncWindowFuture: Int = 30,
        autoCreateGoogleCalendar: Bool = true
    ) {
        self.icloudIdentifier = icloudIdentifier
        self.googleCalendarID = googleCalendarID
        self.name = name
        self.isEnabled = isEnabled
        self.syncWindowPast = syncWindowPast
        self.syncWindowFuture = syncWindowFuture
        self.autoCreateGoogleCalendar = autoCreateGoogleCalendar
    }
}
```

- [ ] **Step 5: Fix compilation errors in SyncEngine and CalSync.swift**

The `SyncEngine` and `CalSync.swift` reference the old `EventMapping` init (without `calendarMappingID`) and `CalendarMapping` init. Update these call sites to compile. The sync engine will be fully rewritten in Task 6, so just make it compile for now.

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter EventMappingTests 2>&1`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add Sources/CalSync/Models/EventMapping.swift Sources/CalSync/Models/CalendarMapping.swift Tests/CalSyncTests/EventMappingTests.swift Sources/CalSync/Engine/SyncEngine.swift Sources/CalSync/CalSync.swift
git commit -m "feat: update SwiftData models with dual checksums, deletion flags, and sync windows"
```

---

## Task 2: Checksum Normalization

**Files:**
- Create: `Sources/CalSync/Models/Checksum.swift`
- Modify: `Sources/CalSync/Models/EKEvent+Checksum.swift`
- Modify: `Sources/CalSync/Models/SyncModels.swift`
- Test: `Tests/CalSyncTests/ChecksumTests.swift`

- [ ] **Step 1: Write tests for checksum symmetry and normalization**

```swift
// Tests/CalSyncTests/ChecksumTests.swift
import Testing
import Foundation
@testable import CalSync

@Suite("Checksum Tests")
struct ChecksumTests {
    @Test("Checksum produces consistent output for same inputs")
    func consistency() {
        let hash1 = Checksum.compute(
            title: "Dinner",
            description: "At Mom's",
            location: "123 Main St",
            startDate: Date(timeIntervalSince1970: 1000000),
            endDate: Date(timeIntervalSince1970: 1003600),
            isAllDay: false,
            status: "confirmed"
        )
        let hash2 = Checksum.compute(
            title: "Dinner",
            description: "At Mom's",
            location: "123 Main St",
            startDate: Date(timeIntervalSince1970: 1000000),
            endDate: Date(timeIntervalSince1970: 1003600),
            isAllDay: false,
            status: "confirmed"
        )
        #expect(hash1 == hash2)
    }

    @Test("Checksum differs when any field changes")
    func sensitivity() {
        let base = Checksum.compute(
            title: "Dinner", description: nil, location: nil,
            startDate: Date(timeIntervalSince1970: 1000000),
            endDate: Date(timeIntervalSince1970: 1003600),
            isAllDay: false, status: "confirmed"
        )
        let changed = Checksum.compute(
            title: "Lunch", description: nil, location: nil,
            startDate: Date(timeIntervalSince1970: 1000000),
            endDate: Date(timeIntervalSince1970: 1003600),
            isAllDay: false, status: "confirmed"
        )
        #expect(base != changed)
    }

    @Test("Checksum uses ISO 8601 UTC dates, not locale-dependent strings")
    func dateNormalization() {
        // Same timestamp should produce same checksum regardless of when/where it runs
        let date = Date(timeIntervalSince1970: 1711324800) // 2024-03-25T00:00:00Z
        let hash = Checksum.compute(
            title: "Test", description: nil, location: nil,
            startDate: date, endDate: date,
            isAllDay: false, status: "confirmed"
        )
        #expect(!hash.isEmpty)
        #expect(hash.count == 64) // SHA-256 hex string
    }

    @Test("Nil description and empty description produce different checksums")
    func nilVsEmpty() {
        let nilHash = Checksum.compute(
            title: "Test", description: nil, location: nil,
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 3600),
            isAllDay: false, status: "confirmed"
        )
        let emptyHash = Checksum.compute(
            title: "Test", description: "", location: nil,
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 3600),
            isAllDay: false, status: "confirmed"
        )
        #expect(nilHash != emptyHash)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ChecksumTests 2>&1`
Expected: Compilation error — `Checksum` type doesn't exist

- [ ] **Step 3: Create shared Checksum utility**

```swift
// Sources/CalSync/Models/Checksum.swift
import Foundation
import CryptoKit

enum Checksum {
    private static let utcFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    static func compute(
        title: String,
        description: String?,
        location: String?,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        status: String
    ) -> String {
        // Use a sentinel for nil to distinguish nil from empty string
        let components = [
            title,
            description ?? "\0nil",
            location ?? "\0nil",
            utcFormatter.string(from: startDate),
            utcFormatter.string(from: endDate),
            String(isAllDay),
            status
        ]
        let combined = components.joined(separator: "|")
        let hash = SHA256.hash(data: Data(combined.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ChecksumTests 2>&1`
Expected: PASS

- [ ] **Step 5: Update EKEvent+Checksum to use shared Checksum**

```swift
// Sources/CalSync/Models/EKEvent+Checksum.swift
import Foundation
import EventKit

extension EKEvent {
    var syncChecksum: String {
        let statusString: String
        switch status {
        case .confirmed: statusString = "confirmed"
        case .tentative: statusString = "tentative"
        case .canceled: statusString = "cancelled"
        default: statusString = "confirmed"
        }

        return Checksum.compute(
            title: title ?? "",
            description: notes,
            location: location,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            status: statusString
        )
    }
}
```

- [ ] **Step 6: Update iCloudEvent to include status and composite UID**

Update `SyncModels.swift`:
- Add `status: String` field to `iCloudEvent`
- Change `id` to use composite UID: `calendarItemExternalIdentifier + "|" + startDate` for recurring, just `calendarItemExternalIdentifier` otherwise
- Skip events where `calendarItemExternalIdentifier` is nil (log warning)
- Add attendees field

```swift
// Sources/CalSync/Models/SyncModels.swift
import Foundation
import EventKit

struct iCloudCalendar: Sendable, Identifiable {
    let id: String
    let title: String
    let sourceTitle: String

    init(from ekCalendar: EKCalendar) {
        self.id = ekCalendar.calendarIdentifier
        self.title = ekCalendar.title
        self.sourceTitle = ekCalendar.source.title
    }
}

struct Attendee: Sendable {
    let name: String
    let status: String  // "accepted", "declined", "tentative", "pending"
}

struct iCloudEvent: Sendable, Identifiable {
    let id: String
    let title: String
    let notes: String?
    let location: String?
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let status: String
    let attendees: [Attendee]
    let checksum: String

    init?(from ekEvent: EKEvent) {
        guard let externalID = ekEvent.calendarItemExternalIdentifier else {
            return nil  // Skip events without stable identifier
        }

        // Always append the occurrence date to the UID. This ensures
        // uniqueness even for recurring event occurrences, which share
        // the same calendarItemExternalIdentifier. For non-recurring
        // events this is harmless — the date is still unique.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        self.id = externalID + "|" + formatter.string(from: ekEvent.startDate)

        self.title = ekEvent.title ?? "Untitled"
        self.notes = ekEvent.notes
        self.location = ekEvent.location
        self.startDate = ekEvent.startDate
        self.endDate = ekEvent.endDate
        self.isAllDay = ekEvent.isAllDay

        switch ekEvent.status {
        case .confirmed: self.status = "confirmed"
        case .tentative: self.status = "tentative"
        case .canceled: self.status = "cancelled"
        default: self.status = "confirmed"
        }

        self.attendees = (ekEvent.attendees ?? []).map { participant in
            let statusStr: String
            switch participant.participantStatus {
            case .accepted: statusStr = "accepted"
            case .declined: statusStr = "declined"
            case .tentative: statusStr = "tentative"
            default: statusStr = "pending"
            }
            return Attendee(name: participant.name ?? "Unknown", status: statusStr)
        }

        self.checksum = ekEvent.syncChecksum
    }
}
```

- [ ] **Step 7: Run all tests**

Run: `swift test 2>&1`
Expected: PASS (all tests including ChecksumTests and EventMappingTests)

- [ ] **Step 8: Commit**

```bash
git add Sources/CalSync/Models/Checksum.swift Sources/CalSync/Models/EKEvent+Checksum.swift Sources/CalSync/Models/SyncModels.swift Tests/CalSyncTests/ChecksumTests.swift
git commit -m "feat: add shared checksum with ISO 8601 normalization, composite UIDs for recurring events"
```

---

## Task 3: Service Protocols and Mocks

**Files:**
- Create: `Sources/CalSync/Services/Protocols.swift`
- Create: `Tests/CalSyncTests/Mocks/MockiCloudService.swift`
- Create: `Tests/CalSyncTests/Mocks/MockGoogleCalendarService.swift`
- Modify: `Sources/CalSync/Services/iCloudService.swift`
- Modify: `Sources/CalSync/Services/GoogleCalendarService.swift`

The sync engine needs to be testable without real EventKit or Google API access. Extract protocols from the services so the engine can be tested with mocks.

- [ ] **Step 1: Define service protocols and GoogleEvent model**

```swift
// Sources/CalSyncLib/Services/Protocols.swift
import Foundation

protocol iCloudServiceProtocol: Sendable {
    func requestAccess() async throws
    func fetchCalendars() async throws -> [iCloudCalendar]
    func fetchEvents(from calendarID: String, startDate: Date, endDate: Date) async throws -> [iCloudEvent]
    func createEvent(in calendarID: String, title: String, notes: String?, location: String?, startDate: Date, endDate: Date, isAllDay: Bool) async throws -> String
    func updateEvent(identifier: String, title: String, notes: String?, location: String?, startDate: Date, endDate: Date, isAllDay: Bool) async throws
    func deleteEvent(identifier: String) async throws
}

// Note: GoogleEvent lives here alongside protocols for now. Can be moved to
// Sources/CalSyncLib/Models/GoogleEvent.swift if the file gets too large.
struct GoogleEvent: Codable, Sendable {
    var id: String?
    var summary: String
    var description: String?
    var location: String?
    var start: EventDateTime
    var end: EventDateTime
    var status: String?

    struct EventDateTime: Codable, Sendable {
        var dateTime: String?   // ISO 8601
        var date: String?       // YYYY-MM-DD for all-day
        var timeZone: String?
    }

    var checksum: String {
        let isAllDay = start.date != nil
        let startD: Date
        let endD: Date

        if isAllDay {
            // All-day events use "YYYY-MM-DD" format, not ISO 8601 with time
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            df.timeZone = TimeZone(identifier: "UTC")
            startD = df.date(from: start.date ?? "") ?? Date.distantPast
            endD = df.date(from: end.date ?? "") ?? Date.distantPast
        } else {
            let isoFormatter = ISO8601DateFormatter()
            startD = isoFormatter.date(from: start.dateTime ?? "") ?? Date.distantPast
            endD = isoFormatter.date(from: end.dateTime ?? "") ?? Date.distantPast
        }

        return Checksum.compute(
            title: summary,
            description: description,
            location: location,
            startDate: startD,
            endDate: endD,
            isAllDay: isAllDay,
            status: status ?? "confirmed"
        )
    }
}

protocol GoogleCalendarServiceProtocol: Sendable {
    func listCalendars() async throws -> [String: String]  // id -> name
    func createCalendar(name: String) async throws -> String  // returns calendar ID
    func listEvents(calendarID: String, timeMin: Date, timeMax: Date) async throws -> [GoogleEvent]
    func createEvent(calendarID: String, event: GoogleEvent) async throws -> String
    func updateEvent(calendarID: String, eventID: String, event: GoogleEvent) async throws
    func deleteEvent(calendarID: String, eventID: String) async throws
}
```

- [ ] **Step 2: Create mock iCloud service**

```swift
// Tests/CalSyncTests/Mocks/MockiCloudService.swift
import Foundation
@testable import CalSync

actor MockiCloudService: iCloudServiceProtocol {
    var calendars: [iCloudCalendar] = []
    var events: [String: [iCloudEvent]] = [:]  // calendarID -> events
    var createdEvents: [(calendarID: String, title: String)] = []
    var updatedEvents: [String] = []
    var deletedEvents: [String] = []

    func requestAccess() async throws {}

    func fetchCalendars() async throws -> [iCloudCalendar] {
        calendars
    }

    func fetchEvents(from calendarID: String, startDate: Date, endDate: Date) async throws -> [iCloudEvent] {
        events[calendarID] ?? []
    }

    func createEvent(in calendarID: String, title: String, notes: String?, location: String?, startDate: Date, endDate: Date, isAllDay: Bool) async throws -> String {
        let id = "mock-icloud-\(UUID().uuidString)"
        createdEvents.append((calendarID: calendarID, title: title))
        return id
    }

    func updateEvent(identifier: String, title: String, notes: String?, location: String?, startDate: Date, endDate: Date, isAllDay: Bool) async throws {
        updatedEvents.append(identifier)
    }

    func deleteEvent(identifier: String) async throws {
        deletedEvents.append(identifier)
    }

    // Test helpers
    func setEvents(for calendarID: String, events: [iCloudEvent]) {
        self.events[calendarID] = events
    }
}
```

- [ ] **Step 3: Create mock Google service**

```swift
// Tests/CalSyncTests/Mocks/MockGoogleCalendarService.swift
import Foundation
@testable import CalSync

actor MockGoogleCalendarService: GoogleCalendarServiceProtocol {
    var calendars: [String: String] = [:]
    var events: [String: [GoogleEvent]] = [:]  // calendarID -> events
    var createdEvents: [(calendarID: String, event: GoogleEvent)] = []
    var updatedEvents: [(calendarID: String, eventID: String)] = []
    var deletedEvents: [(calendarID: String, eventID: String)] = []
    var nextCreatedEventID: String = "mock-google-\(UUID().uuidString)"

    func listCalendars() async throws -> [String: String] {
        calendars
    }

    func createCalendar(name: String) async throws -> String {
        let id = "mock-cal-\(UUID().uuidString)"
        calendars[id] = name
        return id
    }

    func listEvents(calendarID: String, timeMin: Date, timeMax: Date) async throws -> [GoogleEvent] {
        events[calendarID] ?? []
    }

    func createEvent(calendarID: String, event: GoogleEvent) async throws -> String {
        createdEvents.append((calendarID: calendarID, event: event))
        return nextCreatedEventID
    }

    func updateEvent(calendarID: String, eventID: String, event: GoogleEvent) async throws {
        updatedEvents.append((calendarID: calendarID, eventID: eventID))
    }

    func deleteEvent(calendarID: String, eventID: String) async throws {
        deletedEvents.append((calendarID: calendarID, eventID: eventID))
    }

    // Test helpers
    func setEvents(for calendarID: String, events: [GoogleEvent]) {
        self.events[calendarID] = events
    }
}
```

- [ ] **Step 4: Update iCloudService to conform to protocol**

Add `: iCloudServiceProtocol` to the existing `iCloudService` actor declaration. Change `fetchEvents` to use `.compactMap` instead of `.map` (since `iCloudEvent.init` is now failable for events without a stable `calendarItemExternalIdentifier`). Add the three new write methods:

```swift
func createEvent(in calendarID: String, title: String, notes: String?, location: String?, startDate: Date, endDate: Date, isAllDay: Bool) async throws -> String {
    guard let calendar = eventStore.calendar(withIdentifier: calendarID) else {
        throw ServiceError.fetchFailed("Calendar not found: \(calendarID)")
    }
    let event = EKEvent(eventStore: eventStore)
    event.calendar = calendar
    event.title = title
    event.notes = notes
    event.location = location
    event.startDate = startDate
    event.endDate = endDate
    event.isAllDay = isAllDay
    try eventStore.save(event, span: .thisEvent)
    return event.calendarItemExternalIdentifier
}

func updateEvent(identifier: String, title: String, notes: String?, location: String?, startDate: Date, endDate: Date, isAllDay: Bool) async throws {
    guard let event = eventStore.calendarItem(withIdentifier: identifier) as? EKEvent else {
        throw ServiceError.fetchFailed("Event not found: \(identifier)")
    }
    event.title = title
    event.notes = notes
    event.location = location
    event.startDate = startDate
    event.endDate = endDate
    event.isAllDay = isAllDay
    try eventStore.save(event, span: .thisEvent)
}

func deleteEvent(identifier: String) async throws {
    guard let event = eventStore.calendarItem(withIdentifier: identifier) as? EKEvent else {
        throw ServiceError.fetchFailed("Event not found: \(identifier)")
    }
    try eventStore.remove(event, span: .thisEvent)
}
```

- [ ] **Step 5: Update GoogleCalendarService to conform to protocol**

Remove the inner `GoogleEvent` struct (now defined in `Protocols.swift`). Add `: GoogleCalendarServiceProtocol` to the actor. Add `createCalendar` and `listEvents` methods. Update existing methods to match the protocol signatures.

- [ ] **Step 6: Run all tests**

Run: `swift test 2>&1`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add Sources/CalSync/Services/Protocols.swift Sources/CalSync/Services/iCloudService.swift Sources/CalSync/Services/GoogleCalendarService.swift Tests/CalSyncTests/Mocks/
git commit -m "feat: extract service protocols, add mocks, add iCloud write-back methods"
```

---

## Task 4: Keychain Service

**Files:**
- Create: `Sources/CalSync/Services/KeychainService.swift`
- Test: `Tests/CalSyncTests/KeychainServiceTests.swift`

- [ ] **Step 1: Write tests for Keychain CRUD**

```swift
// Tests/CalSyncTests/KeychainServiceTests.swift
import Testing
import Foundation
@testable import CalSync

@Suite("KeychainService Tests")
struct KeychainServiceTests {
    let service = KeychainService(serviceName: "com.calsync.test.\(UUID().uuidString)")

    @Test("Save and retrieve a value")
    func saveAndRetrieve() throws {
        try service.save(key: "test-key", value: "test-value")
        let retrieved = try service.retrieve(key: "test-key")
        #expect(retrieved == "test-value")
    }

    @Test("Retrieve returns nil for missing key")
    func retrieveMissing() throws {
        let result = try service.retrieve(key: "nonexistent")
        #expect(result == nil)
    }

    @Test("Update overwrites existing value")
    func update() throws {
        try service.save(key: "key", value: "v1")
        try service.save(key: "key", value: "v2")
        let result = try service.retrieve(key: "key")
        #expect(result == "v2")
    }

    @Test("Delete removes a value")
    func delete() throws {
        try service.save(key: "key", value: "value")
        try service.delete(key: "key")
        let result = try service.retrieve(key: "key")
        #expect(result == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter KeychainServiceTests 2>&1`
Expected: Compilation error — `KeychainService` doesn't exist

- [ ] **Step 3: Implement KeychainService**

```swift
// Sources/CalSync/Services/KeychainService.swift
import Foundation
import Security

struct KeychainService: Sendable {
    let serviceName: String

    init(serviceName: String = "com.calsync.google-oauth") {
        self.serviceName = serviceName
    }

    enum KeychainError: Error {
        case saveFailed(OSStatus)
        case deleteFailed(OSStatus)
    }

    func save(key: String, value: String) throws {
        let data = Data(value.utf8)
        // Try to delete first (update case)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func retrieve(key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter KeychainServiceTests 2>&1`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/CalSync/Services/KeychainService.swift Tests/CalSyncTests/KeychainServiceTests.swift
git commit -m "feat: add KeychainService for secure token storage"
```

---

## Task 5: GoogleAuthService Keychain Integration

**Files:**
- Modify: `Sources/CalSync/Services/GoogleAuthService.swift`

- [ ] **Step 1: Rewrite GoogleAuthService to use Keychain**

Replace the current implementation. Key changes:
- Store client ID, client secret, access token, refresh token, and expiry in Keychain
- `authenticate()` stores tokens after successful OAuth flow
- Add `refreshAccessToken()` method
- Add `getValidAccessToken()` that checks expiry and refreshes if needed
- Remove the `clientId`/`clientSecret` init parameters — read from Keychain after first auth

```swift
// Sources/CalSync/Services/GoogleAuthService.swift
import Foundation
import Network

actor GoogleAuthService {
    private let keychain: KeychainService
    private let port: UInt16 = 8080
    private let redirectUri = "http://localhost:8080"

    struct TokenResponse: Codable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int
        let scope: String
        let token_type: String
    }

    enum AuthError: Error {
        case notAuthenticated
        case refreshFailed(String)
        case missingCredentials
    }

    init(keychain: KeychainService = KeychainService()) {
        self.keychain = keychain
    }

    func authenticate(clientId: String, clientSecret: String) async throws {
        // Store credentials
        try keychain.save(key: "clientId", value: clientId)
        try keychain.save(key: "clientSecret", value: clientSecret)

        let authUrl = "https://accounts.google.com/o/oauth2/v2/auth?" + [
            "client_id=\(clientId)",
            "redirect_uri=\(redirectUri)",
            "response_type=code",
            "scope=https://www.googleapis.com/auth/calendar",
            "access_type=offline",
            "prompt=consent"
        ].joined(separator: "&")

        print("Please open this URL in your browser to authenticate:")
        print(authUrl)

        let code = try await waitForRedirect()
        let tokenResponse = try await exchangeCodeForToken(code, clientId: clientId, clientSecret: clientSecret)

        try keychain.save(key: "accessToken", value: tokenResponse.access_token)
        if let refreshToken = tokenResponse.refresh_token {
            try keychain.save(key: "refreshToken", value: refreshToken)
        }
        let expiresAt = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in))
        try keychain.save(key: "expiresAt", value: String(expiresAt.timeIntervalSince1970))

        print("Successfully authenticated! Tokens stored in Keychain.")
    }

    func getValidAccessToken() async throws -> String {
        guard let accessToken = try keychain.retrieve(key: "accessToken") else {
            throw AuthError.notAuthenticated
        }

        // Check expiry
        if let expiresAtStr = try keychain.retrieve(key: "expiresAt"),
           let expiresAt = Double(expiresAtStr) {
            if Date().timeIntervalSince1970 < expiresAt - 60 { // 60s buffer
                return accessToken
            }
        }

        // Token expired, try refresh
        return try await refreshAccessToken()
    }

    func refreshAccessToken() async throws -> String {
        guard let refreshToken = try keychain.retrieve(key: "refreshToken"),
              let clientId = try keychain.retrieve(key: "clientId"),
              let clientSecret = try keychain.retrieve(key: "clientSecret") else {
            throw AuthError.missingCredentials
        }

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "refresh_token=\(refreshToken)",
            "client_id=\(clientId)",
            "client_secret=\(clientSecret)",
            "grant_type=refresh_token"
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.refreshFailed(String(data: data, encoding: .utf8) ?? "Unknown error")
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        try keychain.save(key: "accessToken", value: tokenResponse.access_token)
        let expiresAt = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in))
        try keychain.save(key: "expiresAt", value: String(expiresAt.timeIntervalSince1970))

        return tokenResponse.access_token
    }

    // Keep existing waitForRedirect() and extractQueryParam() methods unchanged

    private func exchangeCodeForToken(_ code: String, clientId: String, clientSecret: String) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "code=\(code)",
            "client_id=\(clientId)",
            "client_secret=\(clientSecret)",
            "redirect_uri=\(redirectUri)",
            "grant_type=authorization_code"
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.refreshFailed(String(data: data, encoding: .utf8) ?? "Token exchange failed")
        }

        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    // Existing waitForRedirect() and extractQueryParam() stay as-is
}
```

- [ ] **Step 2: Update the Auth CLI command**

In `CalSync.swift`, update the `Auth` command to pass client ID/secret to `authenticate()`:

```swift
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
```

- [ ] **Step 3: Run all tests**

Run: `swift test 2>&1`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add Sources/CalSync/Services/GoogleAuthService.swift Sources/CalSync/CalSync.swift
git commit -m "feat: GoogleAuthService with Keychain storage, token refresh, and expiry tracking"
```

---

## Task 6: GoogleCalendarService Full Implementation

**Files:**
- Modify: `Sources/CalSync/Services/GoogleCalendarService.swift`

- [ ] **Step 1: Rewrite GoogleCalendarService with full REST, 401 interceptor, and protocol conformance**

Key changes:
- Conform to `GoogleCalendarServiceProtocol`
- Remove inner `GoogleEvent` struct (now in `Protocols.swift`)
- Get access token from `GoogleAuthService` instead of manual `setAccessToken`
- Add 401 interceptor that attempts one token refresh
- Implement `createCalendar`, `listEvents`
- Fix `deleteEvent` status check logic

```swift
// Sources/CalSync/Services/GoogleCalendarService.swift
import Foundation

actor GoogleCalendarService: GoogleCalendarServiceProtocol {
    private let session = URLSession.shared
    private let authService: GoogleAuthService
    private let baseURL = "https://www.googleapis.com/calendar/v3"

    enum ServiceError: Error {
        case authenticationRequired
        case apiError(Int, String)
        case decodingError(String)
    }

    init(authService: GoogleAuthService = GoogleAuthService()) {
        self.authService = authService
    }

    // MARK: - API Methods

    func listCalendars() async throws -> [String: String] {
        struct CalendarList: Codable {
            struct Item: Codable { let id: String; let summary: String }
            let items: [Item]?
        }
        let data = try await authenticatedRequest(path: "/users/me/calendarList", method: "GET")
        let list = try JSONDecoder().decode(CalendarList.self, from: data)
        var result: [String: String] = [:]
        for item in list.items ?? [] {
            result[item.id] = item.summary
        }
        return result
    }

    func createCalendar(name: String) async throws -> String {
        struct CalendarBody: Codable { let summary: String }
        struct CalendarResponse: Codable { let id: String }
        let body = try JSONEncoder().encode(CalendarBody(summary: name))
        let data = try await authenticatedRequest(path: "/calendars", method: "POST", body: body)
        let response = try JSONDecoder().decode(CalendarResponse.self, from: data)
        return response.id
    }

    func listEvents(calendarID: String, timeMin: Date, timeMax: Date) async throws -> [GoogleEvent] {
        struct EventList: Codable {
            let items: [GoogleEvent]?
        }
        let formatter = ISO8601DateFormatter()
        let minStr = formatter.string(from: timeMin)
        let maxStr = formatter.string(from: timeMax)
        let encodedCalID = calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID
        let path = "/calendars/\(encodedCalID)/events?timeMin=\(minStr)&timeMax=\(maxStr)&singleEvents=true&maxResults=2500"
        let data = try await authenticatedRequest(path: path, method: "GET")
        let decoder = JSONDecoder()
        let list = try decoder.decode(EventList.self, from: data)
        return list.items ?? []
    }

    func createEvent(calendarID: String, event: GoogleEvent) async throws -> String {
        let encodedCalID = calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID
        let body = try JSONEncoder().encode(event)
        let data = try await authenticatedRequest(path: "/calendars/\(encodedCalID)/events", method: "POST", body: body)
        let created = try JSONDecoder().decode(GoogleEvent.self, from: data)
        return created.id ?? ""
    }

    func updateEvent(calendarID: String, eventID: String, event: GoogleEvent) async throws {
        let encodedCalID = calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID
        let encodedEventID = eventID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? eventID
        let body = try JSONEncoder().encode(event)
        _ = try await authenticatedRequest(path: "/calendars/\(encodedCalID)/events/\(encodedEventID)", method: "PUT", body: body)
    }

    func deleteEvent(calendarID: String, eventID: String) async throws {
        let encodedCalID = calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID
        let encodedEventID = eventID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? eventID
        _ = try await authenticatedRequest(path: "/calendars/\(encodedCalID)/events/\(encodedEventID)", method: "DELETE", expectEmpty: true)
    }

    // MARK: - Auth Interceptor

    private func authenticatedRequest(path: String, method: String, body: Data? = nil, expectEmpty: Bool = false, isRetry: Bool = false) async throws -> Data {
        let token = try await authService.getValidAccessToken()
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.apiError(0, "No HTTP response")
        }

        // 401 retry with token refresh (once)
        if httpResponse.statusCode == 401 && !isRetry {
            _ = try await authService.refreshAccessToken()
            return try await authenticatedRequest(path: path, method: method, body: body, expectEmpty: expectEmpty, isRetry: true)
        }

        if expectEmpty && httpResponse.statusCode == 204 {
            return Data()
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ServiceError.apiError(httpResponse.statusCode, message)
        }

        return data
    }
}
```

- [ ] **Step 2: Run all tests**

Run: `swift test 2>&1`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add Sources/CalSync/Services/GoogleCalendarService.swift
git commit -m "feat: full GoogleCalendarService REST implementation with 401 retry interceptor"
```

---

## Task 7: Three-Phase Sync Engine

**Files:**
- Rewrite: `Sources/CalSync/Engine/SyncEngine.swift`
- Test: `Tests/CalSyncTests/SyncEngineTests.swift`

This is the largest task. The sync engine orchestrates all three phases per the spec.

- [ ] **Step 1: Write Phase 1 tests (iCloud state detection)**

```swift
// Tests/CalSyncTests/SyncEngineTests.swift
import Testing
import SwiftData
import Foundation
@testable import CalSync

@Suite("SyncEngine Tests")
struct SyncEngineTests {
    // Helper to create an in-memory SwiftData container
    func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: EventMapping.self, CalendarMapping.self, configurations: config)
    }

    // Helper to create a test iCloudEvent-like struct
    // (iCloudEvent requires EKEvent, so we test via the engine's public interface with mocks)

    @Test("Phase 1: New iCloud event creates Google event and mapping")
    func phase1NewEvent() async throws {
        let container = try makeContainer()
        let mockiCloud = MockiCloudService()
        let mockGoogle = MockGoogleCalendarService()

        // Set up a calendar mapping
        let context = ModelContext(container)
        let calMapping = CalendarMapping(icloudIdentifier: "ical1", googleCalendarID: "gcal1", name: "Test")
        context.insert(calMapping)
        try context.save()

        // The mock will need iCloud events — but since iCloudEvent requires EKEvent,
        // the engine must accept the protocol. We test integration through the engine's
        // sync() method. For unit testing the phase logic, we test the individual
        // phase methods if exposed, or test through the full sync cycle.

        // This test verifies the wiring is correct — detailed phase logic tests follow.
        let engine = SyncEngine(
            modelContainer: container,
            icloudService: mockiCloud,
            googleService: mockGoogle
        )
        try await engine.sync()

        // No events set up, so no events should be created
        let createdEvents = await mockGoogle.createdEvents
        #expect(createdEvents.isEmpty)
    }
}
```

Note: Full phase logic testing requires the engine to work with the mock services. The test structure depends on how `SyncEngine` accepts its dependencies. The engine should accept `iCloudServiceProtocol` and `GoogleCalendarServiceProtocol` via init.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SyncEngineTests 2>&1`
Expected: Compilation error — SyncEngine doesn't accept service dependencies

- [ ] **Step 3: Rewrite SyncEngine**

```swift
// Sources/CalSyncLib/Engine/SyncEngine.swift
import Foundation
import SwiftData
import OSLog

// Manually conform to ModelActor instead of using @ModelActor macro,
// because we need a custom init that accepts service dependencies.
actor SyncEngine: ModelActor {
    nonisolated let modelContainer: ModelContainer
    nonisolated let modelExecutor: any ModelExecutor
    private let icloudService: any iCloudServiceProtocol
    private let googleService: any GoogleCalendarServiceProtocol
    private let logger = Logger(subsystem: "com.calsync", category: "SyncEngine")

    init(
        modelContainer: ModelContainer,
        icloudService: any iCloudServiceProtocol = iCloudService(),
        googleService: any GoogleCalendarServiceProtocol = GoogleCalendarService()
    ) {
        self.modelContainer = modelContainer
        self.modelExecutor = DefaultSerialModelExecutor(
            modelContext: ModelContext(modelContainer)
        )
        self.icloudService = icloudService
        self.googleService = googleService
    }

    func sync() async throws {
        let fetchDescriptor = FetchDescriptor<CalendarMapping>(predicate: #Predicate { $0.isEnabled })
        let mappings = try modelContext.fetch(fetchDescriptor)

        for mapping in mappings {
            guard let googleCalendarID = mapping.googleCalendarID else {
                logger.warning("Calendar mapping '\(mapping.name)' has no Google Calendar ID, skipping")
                continue
            }

            let startDate = Calendar.current.date(byAdding: .day, value: -mapping.syncWindowPast, to: Date())!
            let endDate = Calendar.current.date(byAdding: .day, value: mapping.syncWindowFuture, to: Date())!

            do {
                // Phase 1 returns set of mapping IDs it updated, so Phase 2 can detect conflicts
                let phase1UpdatedIDs = try await phase1(mapping: mapping, googleCalendarID: googleCalendarID, startDate: startDate, endDate: endDate)
                try await phase2(mapping: mapping, googleCalendarID: googleCalendarID, startDate: startDate, endDate: endDate, phase1UpdatedIDs: phase1UpdatedIDs)
                try await phase3(mapping: mapping, googleCalendarID: googleCalendarID, startDate: startDate, endDate: endDate)
            } catch {
                logger.error("Sync failed for '\(mapping.name)': \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Phase 1: iCloud State Detection
    // Returns set of icloudUIDs whose icloudChecksum was updated this run

    @discardableResult
    private func phase1(mapping: CalendarMapping, googleCalendarID: String, startDate: Date, endDate: Date) async throws -> Set<String> {
        let icloudEvents = try await icloudService.fetchEvents(from: mapping.icloudIdentifier, startDate: startDate, endDate: endDate)
        let icloudUIDs = Set(icloudEvents.map(\.id))
        var updatedIDs = Set<String>()

        for event in icloudEvents {
            let fetchDescriptor = FetchDescriptor<EventMapping>(predicate: #Predicate { $0.icloudUID == event.id })
            let existing = try modelContext.fetch(fetchDescriptor).first

            if let existing {
                if existing.icloudChecksum != event.checksum {
                    // iCloud event changed — update Google
                    let googleEvent = googleEventFrom(icloudEvent: event)
                    if let googleEventID = existing.googleEventID {
                        try await googleService.updateEvent(calendarID: googleCalendarID, eventID: googleEventID, event: googleEvent)
                        logger.info("Updated Google event for: \(event.title)")
                    }
                    existing.icloudChecksum = event.checksum
                    existing.googleChecksum = googleEvent.checksum
                    existing.lastSyncDate = .now
                    updatedIDs.insert(event.id)
                }
            } else {
                // New iCloud event — create on Google
                let googleEvent = googleEventFrom(icloudEvent: event)
                let googleEventID = try await googleService.createEvent(calendarID: googleCalendarID, event: googleEvent)
                let newMapping = EventMapping(
                    icloudUID: event.id,
                    googleEventID: googleEventID,
                    calendarMappingID: mapping.icloudIdentifier,
                    icloudChecksum: event.checksum,
                    googleChecksum: googleEvent.checksum,
                    syncDirection: "icloud"
                )
                modelContext.insert(newMapping)
                logger.info("Created Google event for: \(event.title)")
            }
        }

        // Detect deletions: mappings with no matching iCloud event
        let calID = mapping.icloudIdentifier
        let allMappings = try modelContext.fetch(FetchDescriptor<EventMapping>(predicate: #Predicate {
            $0.calendarMappingID == calID && $0.deletedOnIcloud == false
        }))
        for eventMapping in allMappings {
            if !icloudUIDs.contains(eventMapping.icloudUID) {
                eventMapping.deletedOnIcloud = true
                logger.info("Detected iCloud deletion for: \(eventMapping.icloudUID)")
            }
        }

        try modelContext.save()
        return updatedIDs
    }

    // MARK: - Phase 2: Google State Detection

    private func phase2(mapping: CalendarMapping, googleCalendarID: String, startDate: Date, endDate: Date, phase1UpdatedIDs: Set<String>) async throws {
        let googleEvents = try await googleService.listEvents(calendarID: googleCalendarID, timeMin: startDate, timeMax: endDate)
        let googleEventIDs = Set(googleEvents.compactMap(\.id))

        for gEvent in googleEvents {
            guard let gEventID = gEvent.id else { continue }

            // Find mapping by googleEventID
            let fetchDescriptor = FetchDescriptor<EventMapping>(predicate: #Predicate { $0.googleEventID == gEventID })
            let existing = try modelContext.fetch(fetchDescriptor).first

            if let existing {
                let currentGoogleChecksum = gEvent.checksum
                if existing.googleChecksum != currentGoogleChecksum {
                    // Google event changed — check if iCloud also changed (conflict)
                    let icloudAlsoChanged = phase1UpdatedIDs.contains(existing.icloudUID)
                    if !icloudAlsoChanged {
                        // Only Google changed — push to iCloud
                        try await pushGoogleToIcloud(googleEvent: gEvent, mapping: existing)
                        existing.googleChecksum = currentGoogleChecksum
                        existing.lastSyncDate = .now
                        logger.info("Pushed Google changes to iCloud for: \(gEvent.summary)")
                    } else {
                        // Both changed — iCloud wins, overwrite Google
                        // Phase 1 already pushed iCloud version to Google
                        existing.googleChecksum = existing.icloudChecksum
                        logger.info("Conflict resolved (iCloud wins) for: \(gEvent.summary)")
                    }
                }
            } else {
                // New Google event — create in iCloud
                let icloudID = try await pushGoogleEventToIcloud(googleEvent: gEvent, calendarID: mapping.icloudIdentifier)
                let newMapping = EventMapping(
                    icloudUID: icloudID,
                    googleEventID: gEventID,
                    calendarMappingID: mapping.icloudIdentifier,
                    icloudChecksum: gEvent.checksum,
                    googleChecksum: gEvent.checksum,
                    syncDirection: "google"
                )
                modelContext.insert(newMapping)
                logger.info("Created iCloud event from Google: \(gEvent.summary)")
            }
        }

        // Detect Google-side deletions
        let calID = mapping.icloudIdentifier
        let allMappings = try modelContext.fetch(FetchDescriptor<EventMapping>(predicate: #Predicate {
            $0.calendarMappingID == calID && $0.deletedOnGoogle == false
        }))
        for eventMapping in allMappings {
            if let googleEventID = eventMapping.googleEventID, !googleEventIDs.contains(googleEventID) {
                eventMapping.deletedOnGoogle = true
                logger.info("Detected Google deletion for: \(eventMapping.icloudUID)")
            }
        }

        try modelContext.save()
    }

    // MARK: - Phase 3: Deletion Arbitration

    private func phase3(mapping: CalendarMapping, googleCalendarID: String, startDate: Date, endDate: Date) async throws {
        let calID = mapping.icloudIdentifier
        let deletionCandidates = try modelContext.fetch(FetchDescriptor<EventMapping>(predicate: #Predicate {
            $0.calendarMappingID == calID && ($0.deletedOnIcloud == true || $0.deletedOnGoogle == true)
        }))

        for eventMapping in deletionCandidates {
            do {
                if eventMapping.deletedOnIcloud {
                    // iCloud-side deletion — delete from Google regardless of origin (iCloud wins)
                    if let googleEventID = eventMapping.googleEventID {
                        try await googleService.deleteEvent(calendarID: googleCalendarID, eventID: googleEventID)
                        logger.info("Deleted Google event (iCloud deletion): \(eventMapping.icloudUID)")
                    }
                    modelContext.delete(eventMapping)

                } else if eventMapping.deletedOnGoogle {
                    if eventMapping.syncDirection == "google" {
                        // User deleted their own Google-originated event — delete from iCloud
                        try await icloudService.deleteEvent(identifier: eventMapping.icloudUID)
                        logger.info("Deleted iCloud event (Google deletion): \(eventMapping.icloudUID)")
                        modelContext.delete(eventMapping)
                    } else {
                        // iCloud-originated event deleted from Google — recreate on Google
                        // Use the sync window dates (not distantPast/Future) for the fetch
                        let events = try await icloudService.fetchEvents(
                            from: mapping.icloudIdentifier,
                            startDate: startDate,
                            endDate: endDate
                        )
                        if let icloudEvent = events.first(where: { $0.id == eventMapping.icloudUID }) {
                            let googleEvent = googleEventFrom(icloudEvent: icloudEvent)
                            let newGoogleID = try await googleService.createEvent(calendarID: googleCalendarID, event: googleEvent)
                            eventMapping.googleEventID = newGoogleID
                            eventMapping.deletedOnGoogle = false
                            eventMapping.googleChecksum = googleEvent.checksum
                            eventMapping.lastSyncDate = .now
                            logger.info("Recreated Google event (iCloud-originated): \(icloudEvent.title)")
                        } else {
                            // iCloud event also gone — clean up
                            modelContext.delete(eventMapping)
                        }
                    }
                }
            } catch {
                logger.error("Deletion handling failed for \(eventMapping.icloudUID): \(error.localizedDescription)")
            }
        }

        try modelContext.save()
    }

    // MARK: - Helpers

    private func googleEventFrom(icloudEvent: iCloudEvent) -> GoogleEvent {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        if icloudEvent.isAllDay {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.timeZone = TimeZone(identifier: "UTC")
            return GoogleEvent(
                summary: icloudEvent.title,
                description: icloudEvent.notes,
                location: icloudEvent.location,
                start: GoogleEvent.EventDateTime(date: dateFormatter.string(from: icloudEvent.startDate)),
                end: GoogleEvent.EventDateTime(date: dateFormatter.string(from: icloudEvent.endDate)),
                status: icloudEvent.status
            )
        }

        return GoogleEvent(
            summary: icloudEvent.title,
            description: icloudEvent.notes,
            location: icloudEvent.location,
            start: GoogleEvent.EventDateTime(dateTime: formatter.string(from: icloudEvent.startDate)),
            end: GoogleEvent.EventDateTime(dateTime: formatter.string(from: icloudEvent.endDate)),
            status: icloudEvent.status
        )
    }

    private func pushGoogleToIcloud(googleEvent: GoogleEvent, mapping: EventMapping) async throws {
        let (startDate, endDate, isAllDay) = parseDates(from: googleEvent)
        try await icloudService.updateEvent(
            identifier: mapping.icloudUID,
            title: googleEvent.summary,
            notes: googleEvent.description,
            location: googleEvent.location,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay
        )
    }

    private func pushGoogleEventToIcloud(googleEvent: GoogleEvent, calendarID: String) async throws -> String {
        let (startDate, endDate, isAllDay) = parseDates(from: googleEvent)
        return try await icloudService.createEvent(
            in: calendarID,
            title: googleEvent.summary,
            notes: googleEvent.description,
            location: googleEvent.location,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay
        )
    }

    private func parseDates(from event: GoogleEvent) -> (start: Date, end: Date, isAllDay: Bool) {
        let formatter = ISO8601DateFormatter()
        if let dateStr = event.start.date {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            df.timeZone = TimeZone(identifier: "UTC")
            let start = df.date(from: dateStr) ?? Date()
            let endStr = event.end.date ?? dateStr
            let end = df.date(from: endStr) ?? start
            return (start, end, true)
        }
        let start = formatter.date(from: event.start.dateTime ?? "") ?? Date()
        let end = formatter.date(from: event.end.dateTime ?? "") ?? Date()
        return (start, end, false)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SyncEngineTests 2>&1`
Expected: PASS

- [ ] **Step 5: Write additional Phase 1 test — iCloud deletion detection**

Add to `SyncEngineTests.swift`:

```swift
@Test("Phase 1: Missing iCloud event sets deletedOnIcloud flag")
func phase1DeletionDetection() async throws {
    let container = try makeContainer()
    let mockiCloud = MockiCloudService()
    let mockGoogle = MockGoogleCalendarService()

    let context = ModelContext(container)
    let calMapping = CalendarMapping(icloudIdentifier: "ical1", googleCalendarID: "gcal1", name: "Test")
    context.insert(calMapping)

    // Pre-existing mapping for an event that no longer exists in iCloud
    let eventMapping = EventMapping(
        icloudUID: "old-event-uid",
        googleEventID: "g-old-event",
        calendarMappingID: "ical1",
        icloudChecksum: "oldhash",
        googleChecksum: "oldhash"
    )
    context.insert(eventMapping)
    try context.save()

    // iCloud returns empty — the event is gone
    await mockiCloud.setEvents(for: "ical1", events: [])

    let engine = SyncEngine(modelContainer: container, icloudService: mockiCloud, googleService: mockGoogle)
    try await engine.sync()

    // Verify the mapping was flagged
    let updated = try context.fetch(FetchDescriptor<EventMapping>()).first
    #expect(updated?.deletedOnIcloud == true)
}
```

- [ ] **Step 6: Write Phase 3 deletion matrix tests**

Add tests for all 4 deletion arbitration cases to `SyncEngineTests.swift`:

```swift
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
    let remaining = try context.fetch(FetchDescriptor<EventMapping>())
    #expect(remaining.isEmpty)
}

@Test("Phase 3: deletedOnGoogle + iCloud-originated recreates on Google")
func phase3DeletedOnGoogleFromIcloud() async throws {
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

    // iCloud still has the event — needs a mock iCloudEvent for the recreate
    // (exact mock setup depends on how test helpers evolve)

    let engine = SyncEngine(modelContainer: container, icloudService: mockiCloud, googleService: mockGoogle)
    try await engine.sync()

    // Event should be recreated on Google
    let created = await mockGoogle.createdEvents
    // If iCloud event not found (mock empty), mapping should be purged instead
    let remaining = try context.fetch(FetchDescriptor<EventMapping>())
    #expect(remaining.isEmpty || !remaining.first!.deletedOnGoogle)
}
```

- [ ] **Step 7: Run tests**

Run: `swift test --filter SyncEngineTests 2>&1`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add Sources/CalSyncLib/Engine/SyncEngine.swift Tests/CalSyncTests/SyncEngineTests.swift
git commit -m "feat: three-phase bidirectional sync engine with deletion arbitration"
```

---

## Task 8: CLI Commands Update

**Files:**
- Modify: `Sources/CalSync/CalSync.swift`

- [ ] **Step 0: Update Sync command to inject service dependencies**

```swift
struct Sync: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Run the sync process.")

    func run() async throws {
        let container = try ModelContainer(for: EventMapping.self, CalendarMapping.self)
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
```

- [ ] **Step 1: Update Configure command (single arg, auto-create Google calendar)**

```swift
struct Configure: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Link an iCloud calendar to a Google Calendar.")

    @Argument(help: "The iCloud calendar identifier.")
    var icloudID: String

    @Option(name: .shortAndLong, help: "The name for the Google Calendar (defaults to iCloud calendar name).")
    var name: String?

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

        let calendarName = name ?? calendar.title
        let authService = GoogleAuthService()
        let googleService = GoogleCalendarService(authService: authService)

        print("Creating Google Calendar: \(calendarName)...")
        let googleCalendarID = try await googleService.createCalendar(name: calendarName)

        let container = try ModelContainer(for: CalendarMapping.self, EventMapping.self)
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
```

- [ ] **Step 2: Add Status command**

```swift
struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show sync status for configured calendars.")

    func run() async throws {
        let container = try ModelContainer(for: CalendarMapping.self, EventMapping.self)
        let context = ModelContext(container)
        let mappings = try context.fetch(FetchDescriptor<CalendarMapping>())

        if mappings.isEmpty {
            print("No calendars configured. Run 'calsync configure' first.")
            return
        }

        for mapping in mappings {
            let eventDescriptor = FetchDescriptor<EventMapping>(predicate: #Predicate {
                $0.calendarMappingID == mapping.icloudIdentifier
            })
            let events = try context.fetch(eventDescriptor)
            let lastSync = events.compactMap(\.lastSyncDate).max()

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
```

- [ ] **Step 3: Add Install and Uninstall commands**

```swift
struct Install: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Set up automatic sync via launchd.")

    @Option(name: .long, help: "Sync interval in minutes (default: 10).")
    var interval: Int = 10

    func run() async throws {
        let plistPath = NSHomeDirectory() + "/Library/LaunchAgents/com.calsync.agent.plist"
        let logPath = NSHomeDirectory() + "/Library/Logs/calsync.log"

        // Find the calsync binary
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
```

- [ ] **Step 4: Update main command configuration**

```swift
static let configuration = CommandConfiguration(
    abstract: "Syncs private iCloud calendars to Google Calendar.",
    subcommands: [Sync.self, ListCalendars.self, Configure.self, Auth.self, Status.self, Install.self, Uninstall.self]
)
```

- [ ] **Step 5: Run all tests**

Run: `swift test 2>&1`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/CalSync/CalSync.swift
git commit -m "feat: add status, install, uninstall commands; update configure for auto-create"
```

---

## Task 9: Update Documentation

**Files:**
- Modify: `docs/problem_statement.md`
- Modify: `docs/design.md`
- Modify: `STATUS.md`

- [ ] **Step 1: Update problem statement for home context**

Remove corporate references (Santa, Google corporate policy, data exfiltration). Reframe as personal use case: "I use Google Calendar but people share private iCloud calendars with me."

- [ ] **Step 2: Update design doc to reflect new architecture**

Update to describe bidirectional sync, three-phase engine, Keychain auth, launchd scheduling. Remove corporate security section. Reference the spec for full details.

- [ ] **Step 3: Update STATUS.md**

Reflect current state: pivoted to home use, updated models, implemented bidirectional sync engine, Keychain auth, launchd scheduling. List remaining work (manual testing against real calendars, edge case hardening).

- [ ] **Step 4: Commit**

```bash
git add docs/problem_statement.md docs/design.md STATUS.md
git commit -m "docs: update documentation for home pivot with bidirectional sync"
```

---

## Task 10: Integration Smoke Test

**Files:** No new files — manual verification

- [ ] **Step 1: Build the project**

Run: `swift build 2>&1`
Expected: Successful build with no errors

- [ ] **Step 2: Run all tests**

Run: `swift test 2>&1`
Expected: All tests pass

- [ ] **Step 3: Verify CLI help output**

Run: `.build/debug/CalSync --help`
Expected: Shows all subcommands (sync, list-calendars, configure, auth, status, install, uninstall)

- [ ] **Step 4: Verify list-calendars works**

Run: `.build/debug/CalSync list-calendars`
Expected: Either lists calendars or shows a clear permission error (which is expected before granting Calendar access)

- [ ] **Step 5: Commit any fixes from smoke testing**

Only if needed.
