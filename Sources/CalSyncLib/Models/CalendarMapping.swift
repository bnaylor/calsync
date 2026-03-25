import Foundation
import SwiftData

@Model
public final class CalendarMapping {
    @Attribute(.unique) public var icloudIdentifier: String
    public var googleCalendarID: String?
    public var name: String
    public var isEnabled: Bool

    public init(icloudIdentifier: String, googleCalendarID: String? = nil, name: String, isEnabled: Bool = true) {
        self.icloudIdentifier = icloudIdentifier
        self.googleCalendarID = googleCalendarID
        self.name = name
        self.isEnabled = isEnabled
    }
}
