import Testing
@testable import CalSyncLib

@Suite("CalSync Core Tests")
struct CalSyncTests {
    @Test("Basic logic check")
    func example() async throws {
        #expect(1 + 1 == 2)
    }
}
