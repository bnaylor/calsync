import Foundation
import EventKit

/// Sendable representation of an iCloud Calendar
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

/// Sendable representation of an iCloud Event
public struct iCloudEvent: Sendable, Identifiable {
    public let id: String
    public let title: String
    public let notes: String?
    public let location: String?
    public let startDate: Date
    public let endDate: Date
    public let isAllDay: Bool
    public let checksum: String

    public init(from ekEvent: EKEvent) {
        self.id = ekEvent.calendarItemExternalIdentifier ?? ekEvent.eventIdentifier
        self.title = ekEvent.title ?? "Untitled"
        self.notes = ekEvent.notes
        self.location = ekEvent.location
        self.startDate = ekEvent.startDate
        self.endDate = ekEvent.endDate
        self.isAllDay = ekEvent.isAllDay
        self.checksum = ekEvent.syncChecksum
    }
}
