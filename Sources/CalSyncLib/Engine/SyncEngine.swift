import Foundation
import SwiftData
import OSLog

public actor SyncEngine: ModelActor {
    nonisolated public let modelContainer: ModelContainer
    nonisolated public let modelExecutor: any ModelExecutor
    private let icloudService: any iCloudServiceProtocol
    private let googleService: any GoogleCalendarServiceProtocol
    private let logger = Logger(subsystem: "com.calsync", category: "SyncEngine")

    public init(
        modelContainer: ModelContainer,
        icloudService: any iCloudServiceProtocol = iCloudService(),
        googleService: any GoogleCalendarServiceProtocol = GoogleCalendarService()
    ) {
        self.modelContainer = modelContainer
        self.modelExecutor = DefaultSerialModelExecutor(
            modelContext: ModelContext(modelContainer)
        )
        self.icloudService = icloudService
        self.googleService = googleService
    }

    public func sync() async throws {
        let fetchDescriptor = FetchDescriptor<CalendarMapping>(predicate: #Predicate { $0.isEnabled })
        let mappings = try modelContext.fetch(fetchDescriptor)

        for mapping in mappings {
            guard let googleCalendarID = mapping.googleCalendarID else {
                logger.warning("Calendar mapping '\(mapping.name)' has no Google Calendar ID, skipping")
                continue
            }

            let startDate = Calendar.current.date(byAdding: .day, value: -mapping.syncWindowPast, to: Date())!
            let endDate = Calendar.current.date(byAdding: .day, value: mapping.syncWindowFuture, to: Date())!

            do {
                let phase1UpdatedIDs = try await phase1(mapping: mapping, googleCalendarID: googleCalendarID, startDate: startDate, endDate: endDate)
                try await phase2(mapping: mapping, googleCalendarID: googleCalendarID, startDate: startDate, endDate: endDate, phase1UpdatedIDs: phase1UpdatedIDs)
                try await phase3(mapping: mapping, googleCalendarID: googleCalendarID, startDate: startDate, endDate: endDate)
            } catch {
                logger.error("Sync failed for '\(mapping.name)': \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Phase 1: iCloud State Detection

    @discardableResult
    private func phase1(mapping: CalendarMapping, googleCalendarID: String, startDate: Date, endDate: Date) async throws -> Set<String> {
        let icloudEvents = try await icloudService.fetchEvents(from: mapping.icloudIdentifier, startDate: startDate, endDate: endDate)
        let icloudUIDs = Set(icloudEvents.map(\.id))
        var updatedIDs = Set<String>()

        for event in icloudEvents {
            let eventID = event.id
            let fetchDescriptor = FetchDescriptor<EventMapping>(predicate: #Predicate { $0.icloudUID == eventID })
            let existing = try modelContext.fetch(fetchDescriptor).first

            if let existing {
                if existing.icloudChecksum != event.checksum {
                    let googleEvent = googleEventFrom(icloudEvent: event)
                    if let googleEventID = existing.googleEventID {
                        try await googleService.updateEvent(calendarID: googleCalendarID, eventID: googleEventID, event: googleEvent)
                        logger.info("Updated Google event for: \(event.title)")
                    }
                    existing.icloudChecksum = event.checksum
                    existing.googleChecksum = googleEvent.checksum
                    existing.lastSyncDate = .now
                    updatedIDs.insert(event.id)
                }
            } else {
                let googleEvent = googleEventFrom(icloudEvent: event)
                let googleEventID = try await googleService.createEvent(calendarID: googleCalendarID, event: googleEvent)
                let newMapping = EventMapping(
                    icloudUID: event.id,
                    googleEventID: googleEventID,
                    calendarMappingID: mapping.icloudIdentifier,
                    icloudChecksum: event.checksum,
                    googleChecksum: googleEvent.checksum,
                    syncDirection: "icloud"
                )
                modelContext.insert(newMapping)
                logger.info("Created Google event for: \(event.title)")
            }
        }

        // Detect deletions: mappings with no matching iCloud event
        let calID = mapping.icloudIdentifier
        let allMappings = try modelContext.fetch(FetchDescriptor<EventMapping>(predicate: #Predicate {
            $0.calendarMappingID == calID && $0.deletedOnIcloud == false
        }))
        for eventMapping in allMappings {
            if !icloudUIDs.contains(eventMapping.icloudUID) {
                eventMapping.deletedOnIcloud = true
                logger.info("Detected iCloud deletion for: \(eventMapping.icloudUID)")
            }
        }

        try modelContext.save()
        return updatedIDs
    }

    // MARK: - Phase 2: Google State Detection

    private func phase2(mapping: CalendarMapping, googleCalendarID: String, startDate: Date, endDate: Date, phase1UpdatedIDs: Set<String>) async throws {
        let googleEvents = try await googleService.listEvents(calendarID: googleCalendarID, timeMin: startDate, timeMax: endDate)
        let googleEventIDs = Set(googleEvents.compactMap(\.id))

        for gEvent in googleEvents {
            guard let gEventID = gEvent.id else { continue }

            let fetchDescriptor = FetchDescriptor<EventMapping>(predicate: #Predicate { $0.googleEventID == gEventID })
            let existing = try modelContext.fetch(fetchDescriptor).first

            if let existing {
                let currentGoogleChecksum = gEvent.checksum
                if existing.googleChecksum != currentGoogleChecksum {
                    let icloudAlsoChanged = phase1UpdatedIDs.contains(existing.icloudUID)
                    if !icloudAlsoChanged {
                        try await pushGoogleToIcloud(googleEvent: gEvent, mapping: existing)
                        existing.googleChecksum = currentGoogleChecksum
                        existing.lastSyncDate = .now
                        logger.info("Pushed Google changes to iCloud for: \(gEvent.summary)")
                    } else {
                        // Phase 1 already pushed iCloud version to Google and set googleChecksum — no action needed
                        logger.info("Conflict resolved (iCloud wins) for: \(gEvent.summary)")
                    }
                }
            } else {
                let icloudID = try await pushGoogleEventToIcloud(googleEvent: gEvent, calendarID: mapping.icloudIdentifier)
                let newMapping = EventMapping(
                    icloudUID: icloudID,
                    googleEventID: gEventID,
                    calendarMappingID: mapping.icloudIdentifier,
                    icloudChecksum: gEvent.checksum,
                    googleChecksum: gEvent.checksum,
                    syncDirection: "google"
                )
                modelContext.insert(newMapping)
                logger.info("Created iCloud event from Google: \(gEvent.summary)")
            }
        }

        // Detect Google-side deletions
        let calID = mapping.icloudIdentifier
        let allMappings = try modelContext.fetch(FetchDescriptor<EventMapping>(predicate: #Predicate {
            $0.calendarMappingID == calID && $0.deletedOnGoogle == false
        }))
        for eventMapping in allMappings {
            if let googleEventID = eventMapping.googleEventID, !googleEventIDs.contains(googleEventID) {
                eventMapping.deletedOnGoogle = true
                logger.info("Detected Google deletion for: \(eventMapping.icloudUID)")
            }
        }

        try modelContext.save()
    }

    // MARK: - Phase 3: Deletion Arbitration

    private func phase3(mapping: CalendarMapping, googleCalendarID: String, startDate: Date, endDate: Date) async throws {
        let calID = mapping.icloudIdentifier
        let deletionCandidates = try modelContext.fetch(FetchDescriptor<EventMapping>(predicate: #Predicate {
            $0.calendarMappingID == calID && ($0.deletedOnIcloud == true || $0.deletedOnGoogle == true)
        }))

        for eventMapping in deletionCandidates {
            do {
                if eventMapping.deletedOnIcloud {
                    if let googleEventID = eventMapping.googleEventID {
                        try await googleService.deleteEvent(calendarID: googleCalendarID, eventID: googleEventID)
                        logger.info("Deleted Google event (iCloud deletion): \(eventMapping.icloudUID)")
                    }
                    modelContext.delete(eventMapping)

                } else if eventMapping.deletedOnGoogle {
                    if eventMapping.syncDirection == "google" {
                        try await icloudService.deleteEvent(identifier: eventMapping.icloudUID)
                        logger.info("Deleted iCloud event (Google deletion): \(eventMapping.icloudUID)")
                        modelContext.delete(eventMapping)
                    } else {
                        let events = try await icloudService.fetchEvents(
                            from: mapping.icloudIdentifier,
                            startDate: startDate,
                            endDate: endDate
                        )
                        if let icloudEvent = events.first(where: { $0.id == eventMapping.icloudUID }) {
                            let googleEvent = googleEventFrom(icloudEvent: icloudEvent)
                            let newGoogleID = try await googleService.createEvent(calendarID: googleCalendarID, event: googleEvent)
                            eventMapping.googleEventID = newGoogleID
                            eventMapping.deletedOnGoogle = false
                            eventMapping.googleChecksum = googleEvent.checksum
                            eventMapping.lastSyncDate = .now
                            logger.info("Recreated Google event (iCloud-originated): \(icloudEvent.title)")
                        } else {
                            modelContext.delete(eventMapping)
                        }
                    }
                }
            } catch {
                logger.error("Deletion handling failed for \(eventMapping.icloudUID): \(error.localizedDescription)")
            }
        }

        try modelContext.save()
    }

    // MARK: - Helpers

    private func googleEventFrom(icloudEvent: iCloudEvent) -> GoogleEvent {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        if icloudEvent.isAllDay {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.timeZone = TimeZone(identifier: "UTC")
            return GoogleEvent(
                summary: icloudEvent.title,
                description: icloudEvent.notes,
                location: icloudEvent.location,
                start: GoogleEvent.EventDateTime(date: dateFormatter.string(from: icloudEvent.startDate)),
                end: GoogleEvent.EventDateTime(date: dateFormatter.string(from: icloudEvent.endDate)),
                status: icloudEvent.status
            )
        }

        return GoogleEvent(
            summary: icloudEvent.title,
            description: icloudEvent.notes,
            location: icloudEvent.location,
            start: GoogleEvent.EventDateTime(dateTime: formatter.string(from: icloudEvent.startDate)),
            end: GoogleEvent.EventDateTime(dateTime: formatter.string(from: icloudEvent.endDate)),
            status: icloudEvent.status
        )
    }

    private func pushGoogleToIcloud(googleEvent: GoogleEvent, mapping: EventMapping) async throws {
        let (startDate, endDate, isAllDay) = parseDates(from: googleEvent)
        try await icloudService.updateEvent(
            identifier: mapping.icloudUID,
            title: googleEvent.summary,
            notes: googleEvent.description,
            location: googleEvent.location,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay
        )
    }

    private func pushGoogleEventToIcloud(googleEvent: GoogleEvent, calendarID: String) async throws -> String {
        let (startDate, endDate, isAllDay) = parseDates(from: googleEvent)
        return try await icloudService.createEvent(
            in: calendarID,
            title: googleEvent.summary,
            notes: googleEvent.description,
            location: googleEvent.location,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay
        )
    }

    private func parseDates(from event: GoogleEvent) -> (start: Date, end: Date, isAllDay: Bool) {
        let formatter = ISO8601DateFormatter()
        if let dateStr = event.start.date {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            df.timeZone = TimeZone(identifier: "UTC")
            let start = df.date(from: dateStr) ?? Date()
            let endStr = event.end.date ?? dateStr
            let end = df.date(from: endStr) ?? start
            return (start, end, true)
        }
        let start = formatter.date(from: event.start.dateTime ?? "") ?? Date()
        let end = formatter.date(from: event.end.dateTime ?? "") ?? Date()
        return (start, end, false)
    }
}
