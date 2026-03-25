import Foundation
import EventKit

public struct iCloudCalendar: Sendable, Identifiable {
    public let id: String
    public let title: String
    public let sourceTitle: String

    public init(from ekCalendar: EKCalendar) {
        self.id = ekCalendar.calendarIdentifier
        self.title = ekCalendar.title
        self.sourceTitle = ekCalendar.source.title
    }
}

public struct Attendee: Sendable {
    public let name: String
    public let status: String

    public init(name: String, status: String) {
        self.name = name
        self.status = status
    }
}

public struct iCloudEvent: Sendable, Identifiable {
    public let id: String
    public let title: String
    public let notes: String?
    public let location: String?
    public let startDate: Date
    public let endDate: Date
    public let isAllDay: Bool
    public let status: String
    public let attendees: [Attendee]
    public let checksum: String

    public init?(from ekEvent: EKEvent) {
        guard let externalID = ekEvent.calendarItemExternalIdentifier else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        self.id = externalID + "|" + formatter.string(from: ekEvent.startDate)

        self.title = ekEvent.title ?? "Untitled"
        self.notes = ekEvent.notes
        self.location = ekEvent.location
        self.startDate = ekEvent.startDate
        self.endDate = ekEvent.endDate
        self.isAllDay = ekEvent.isAllDay

        switch ekEvent.status {
        case .confirmed: self.status = "confirmed"
        case .tentative: self.status = "tentative"
        case .canceled: self.status = "cancelled"
        default: self.status = "confirmed"
        }

        self.attendees = (ekEvent.attendees ?? []).map { participant in
            let statusStr: String
            switch participant.participantStatus {
            case .accepted: statusStr = "accepted"
            case .declined: statusStr = "declined"
            case .tentative: statusStr = "tentative"
            default: statusStr = "pending"
            }
            return Attendee(name: participant.name ?? "Unknown", status: statusStr)
        }

        self.checksum = ekEvent.syncChecksum
    }
}
