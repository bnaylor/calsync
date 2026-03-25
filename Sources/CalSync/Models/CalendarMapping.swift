import Foundation
import SwiftData

@Model
final class CalendarMapping {
    @Attribute(.unique) var icloudIdentifier: String
    var googleCalendarID: String?
    var name: String
    var isEnabled: Bool
    
    init(icloudIdentifier: String, googleCalendarID: String? = nil, name: String, isEnabled: Bool = true) {
        self.icloudIdentifier = icloudIdentifier
        self.googleCalendarID = googleCalendarID
        self.name = name
        self.isEnabled = isEnabled
    }
}
