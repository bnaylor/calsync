import Foundation
import SwiftData

@Model
public final class EventMapping {
    @Attribute(.unique) public var icloudUID: String
    public var googleEventID: String?
    public var calendarMappingID: String
    public var lastSyncDate: Date
    public var icloudChecksum: String?
    public var googleChecksum: String?
    public var syncDirection: String
    public var deletedOnIcloud: Bool
    public var deletedOnGoogle: Bool

    public init(
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
