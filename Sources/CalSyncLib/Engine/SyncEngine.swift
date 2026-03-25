import Foundation
import SwiftData
import EventKit

@ModelActor
public actor SyncEngine {
    private let icloudService = iCloudService()
    private let googleService = GoogleCalendarService()
    
    public func sync() async throws {
        // Fetch enabled calendar mappings
        let fetchDescriptor = FetchDescriptor<CalendarMapping>(predicate: #Predicate { $0.isEnabled })
        let mappings = try modelContext.fetch(fetchDescriptor)
        
        for mapping in mappings {
            try await syncCalendar(mapping)
        }
    }
    
    private func syncCalendar(_ mapping: CalendarMapping) async throws {
        guard let googleCalendarID = mapping.googleCalendarID else { return }
        
        let calendars = try await icloudService.fetchCalendars()
        guard let _ = calendars.first(where: { $0.id == mapping.icloudIdentifier }) else {
            print("Could not find iCloud calendar with identifier: \(mapping.icloudIdentifier)")
            return
        }
        
        // Fetch events for the next 30 days
        let startDate = Date()
        let endDate = Calendar.current.date(byAdding: .day, value: 30, to: startDate)!
        let events = try await icloudService.fetchEvents(from: mapping.icloudIdentifier, startDate: startDate, endDate: endDate)
        
        for event in events {
            try await syncEvent(event, googleCalendarID: googleCalendarID)
        }
    }
    
    private func syncEvent(_ event: iCloudEvent, googleCalendarID: String) async throws {
        let icloudUID = event.id
        let currentChecksum = event.checksum
        
        // Check if we already have a mapping for this event
        let fetchDescriptor = FetchDescriptor<EventMapping>(predicate: #Predicate { $0.icloudUID == icloudUID })
        let mappings = try modelContext.fetch(fetchDescriptor)
        let mapping = mappings.first
        
        if let existingMapping = mapping {
            if let googleEventID = existingMapping.googleEventID {
                if existingMapping.icloudChecksum != currentChecksum {
                    // Update existing event if checksum has changed
                    print("Updating existing event: \(event.title) (Google ID: \(googleEventID))")

                    // In a real implementation:
                    // try await googleService.updateEvent(calendarID: googleCalendarID, eventID: googleEventID, event: ...)

                    existingMapping.icloudChecksum = currentChecksum
                    existingMapping.lastSyncDate = .now
                } else {
                    // No changes needed
                }
            }
        } else {
            // Create new event in Google Calendar
            print("Creating new event in Google: \(event.title)")
            
            // In a real implementation:
            // let googleEventID = try await googleService.createEvent(calendarID: googleCalendarID, event: ...)
            let dummyID = "dummy-id-\(UUID().uuidString)"
            
            // Save mapping
            let newMapping = EventMapping(
                icloudUID: icloudUID,
                googleEventID: dummyID,
                calendarMappingID: "",
                icloudChecksum: currentChecksum
            )
            modelContext.insert(newMapping)
        }
        
        try modelContext.save()
    }
}
