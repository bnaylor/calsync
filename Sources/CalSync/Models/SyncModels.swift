import Foundation
import EventKit

/// Sendable representation of an iCloud Calendar
struct iCloudCalendar: Sendable, Identifiable {
    let id: String
    let title: String
    let sourceTitle: String
    
    init(from ekCalendar: EKCalendar) {
        self.id = ekCalendar.calendarIdentifier
        self.title = ekCalendar.title
        self.sourceTitle = ekCalendar.source.title
    }
}

/// Sendable representation of an iCloud Event
struct iCloudEvent: Sendable, Identifiable {
    let id: String
    let title: String
    let notes: String?
    let location: String?
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let checksum: String
    
    init(from ekEvent: EKEvent) {
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
