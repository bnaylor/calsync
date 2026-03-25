import Testing
import Foundation
@testable import CalSyncLib

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
