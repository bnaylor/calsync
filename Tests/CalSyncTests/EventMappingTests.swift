import Testing
import SwiftData
@testable import CalSyncLib

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
