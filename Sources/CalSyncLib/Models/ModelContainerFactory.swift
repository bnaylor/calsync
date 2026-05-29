import Foundation
import SwiftData

public enum ModelContainerFactory {
    public static func makeContainer() throws -> ModelContainer {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let storeDir = appSupport.appendingPathComponent("CalSync")
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        let storeURL = storeDir.appendingPathComponent("default.store")
        let schema = Schema([CalendarMapping.self, EventMapping.self])
        let config = ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
