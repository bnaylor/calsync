import Foundation
import SwiftData

@Model
final class EventMapping {
    @Attribute(.unique) var icloudUID: String
    var googleEventID: String?
    var lastSyncDate: Date
    var checksum: String? // To detect changes in the iCloud event
    
    init(icloudUID: String, googleEventID: String? = nil, lastSyncDate: Date = .now, checksum: String? = nil) {
        self.icloudUID = icloudUID
        self.googleEventID = googleEventID
        self.lastSyncDate = lastSyncDate
        self.checksum = checksum
    }
}
