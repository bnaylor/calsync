import Foundation
import SwiftData

@Model
public final class CalendarMapping {
    @Attribute(.unique) public var icloudIdentifier: String
    public var googleCalendarID: String?
    public var name: String
    public var isEnabled: Bool
    public var syncWindowPast: Int
    public var syncWindowFuture: Int
    public var autoCreateGoogleCalendar: Bool

    public init(
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
