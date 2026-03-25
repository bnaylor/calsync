import Foundation
import EventKit

extension EKEvent {
    public var syncChecksum: String {
        let statusString: String
        switch status {
        case .confirmed: statusString = "confirmed"
        case .tentative: statusString = "tentative"
        case .canceled: statusString = "cancelled"
        default: statusString = "confirmed"
        }
        return Checksum.compute(
            title: title ?? "",
            description: notes,
            location: location,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            status: statusString
        )
    }
}
