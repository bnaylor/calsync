# CalSync Design Document

## Overview
CalSync is a macOS command-line utility designed to bridge the gap between private iCloud calendars and Google Calendar. It provides a "single pane of glass" view in Google Calendar by syncing events from iCloud accounts that are otherwise inaccessible via corporate-managed Google Calendar subscriptions.

## Architecture

### Technical Stack
- **Language:** Swift 6.2 (Strict Concurrency)
- **Frameworks:**
  - **EventKit:** Native macOS access to the local Calendar database (iCloud).
  - **SwiftData:** Local persistence for event mapping and state tracking.
  - **ArgumentParser:** CLI command and option management.
- **APIs:** Google Calendar REST API (v3) via `URLSession`.

### Components

#### 1. Services Layer
- **`iCloudService` (Actor):** Wraps `EventKit`. Handles permission requests and fetches events/calendars from the system's local calendar store. Being an actor ensures thread-safe access to the underlying `EKEventStore`.
- **`GoogleCalendarService` (Actor):** Manages OAuth2 authentication and REST communication with Google. It handles the mapping of Swift models to Google Calendar JSON structures.

#### 2. Data Layer (SwiftData)
- **`CalendarMapping`:** Stores the link between an iCloud calendar identifier and a Google Calendar ID. Tracks whether sync is enabled for that specific pair.
- **`EventMapping`:** The core of the sync engine. It maps an `icloudUID` to a `googleEventID`. It also stores a `checksum` (hash of event details) to detect changes on the iCloud side and a `lastSyncDate`.

#### 3. Sync Engine
- **`SyncEngine` (ModelActor):** Orchestrates the sync process.
  - **P0 (One-way):** Fetches iCloud events, checks the `EventMapping` for an existing `googleEventID`. If missing, it creates the event in Google. If present but the checksum differs, it updates the Google event.
  - **P1 (Two-way):** (Planned) Monitors Google Calendar for changes and pushes them back to the iCloud `EKEvent` via EventKit.

## Security & Compliance
The design acknowledges corporate policies intended to prevent accidental data exfiltration from Google Workspace to personal iCloud accounts.
1. **Unidirectional by Default (P0):** The primary focus is a read-only sync from iCloud to Google. This allows the user to see their personal commitments alongside work ones without ever moving sensitive corporate event data into the iCloud ecosystem.
2. **Controlled Back-Sync (P1):** If two-way sync is implemented, it will be strictly limited to events that originated in iCloud or specifically tagged/filtered events to ensure corporate meeting details (attendees, notes, meet links) are never synced back to personal accounts.
3. **Local Execution:** By using `EventKit` and local SwiftData, we avoid intermediate cloud services or third-party servers that would otherwise handle sensitive tokens or event data.

## Workflow
1. **Discovery:** User runs `calsync list-calendars` to see available iCloud calendars.
2. **Configuration:** User maps an iCloud calendar to a target Google Calendar.
3. **Sync:** User runs `calsync sync`.
   - Engine fetches iCloud events for the configured window (e.g., -7 to +30 days).
   - Engine reconciles state using the SwiftData store.
   - Engine pushes necessary changes to Google Calendar API.

## Future Roadmap
- **OAuth2 Flow:** Implement a local redirect server for the initial Google Calendar authorization.
- **Delta Sync:** Use sync tokens where possible to minimize API usage.
- **Deletion Handling:** Logic to remove events from Google if they are deleted from iCloud.
