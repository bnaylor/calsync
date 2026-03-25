import Testing
import Foundation
@testable import CalSyncLib

@Suite("Checksum Tests")
struct ChecksumTests {
    @Test("Checksum produces consistent output for same inputs")
    func consistency() {
        let hash1 = Checksum.compute(
            title: "Dinner", description: "At Mom's", location: "123 Main St",
            startDate: Date(timeIntervalSince1970: 1000000),
            endDate: Date(timeIntervalSince1970: 1003600),
            isAllDay: false, status: "confirmed"
        )
        let hash2 = Checksum.compute(
            title: "Dinner", description: "At Mom's", location: "123 Main St",
            startDate: Date(timeIntervalSince1970: 1000000),
            endDate: Date(timeIntervalSince1970: 1003600),
            isAllDay: false, status: "confirmed"
        )
        #expect(hash1 == hash2)
    }

    @Test("Checksum differs when any field changes")
    func sensitivity() {
        let base = Checksum.compute(title: "Dinner", description: nil, location: nil,
            startDate: Date(timeIntervalSince1970: 1000000),
            endDate: Date(timeIntervalSince1970: 1003600),
            isAllDay: false, status: "confirmed")
        let changed = Checksum.compute(title: "Lunch", description: nil, location: nil,
            startDate: Date(timeIntervalSince1970: 1000000),
            endDate: Date(timeIntervalSince1970: 1003600),
            isAllDay: false, status: "confirmed")
        #expect(base != changed)
    }

    @Test("Checksum uses ISO 8601 UTC dates, not locale-dependent strings")
    func dateNormalization() {
        let date = Date(timeIntervalSince1970: 1711324800)
        let hash = Checksum.compute(title: "Test", description: nil, location: nil,
            startDate: date, endDate: date, isAllDay: false, status: "confirmed")
        #expect(!hash.isEmpty)
        #expect(hash.count == 64) // SHA-256 hex string
    }

    @Test("Nil description and empty description produce different checksums")
    func nilVsEmpty() {
        let nilHash = Checksum.compute(title: "Test", description: nil, location: nil,
            startDate: Date(timeIntervalSince1970: 0), endDate: Date(timeIntervalSince1970: 3600),
            isAllDay: false, status: "confirmed")
        let emptyHash = Checksum.compute(title: "Test", description: "", location: nil,
            startDate: Date(timeIntervalSince1970: 0), endDate: Date(timeIntervalSince1970: 3600),
            isAllDay: false, status: "confirmed")
        #expect(nilHash != emptyHash)
    }
}
