import Foundation
import SwiftData

@Model
public final class EventMapping {
    @Attribute(.unique) public var icloudUID: String
    public var googleEventID: String?
    public var lastSyncDate: Date
    public var checksum: String? // To detect changes in the iCloud event

    public init(icloudUID: String, googleEventID: String? = nil, lastSyncDate: Date = .now, checksum: String? = nil) {
        self.icloudUID = icloudUID
        self.googleEventID = googleEventID
        self.lastSyncDate = lastSyncDate
        self.checksum = checksum
    }
}
