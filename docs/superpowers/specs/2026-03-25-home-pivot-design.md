# CalSync Home Pivot — Design Spec

## Overview

CalSync is a macOS CLI tool that bidirectionally syncs private shared iCloud calendars with Google Calendar. It enables Google Calendar as a single pane of glass for event management, including privately shared Apple calendars that Google Calendar cannot natively subscribe to.

This spec covers the pivot from a corporate use case (read-only sync with data exfiltration safeguards) to a personal/home use case with full two-way sync.

## Use Case

The user's primary calendar app is Google Calendar. Other people (family, friends) share private iCloud calendars with the user. Google Calendar cannot subscribe to private iCloud calendar URLs. CalSync bridges this gap by syncing events between the local EventKit database (which can access shared iCloud calendars) and Google Calendar via the REST API.

### Sync Capabilities

- Create, update, reschedule, and delete events on either side
- Accept/decline invitations from Google
- Create new events on shared iCloud calendars from Google
- Full read/write parity except that title/description edits are lower priority

### Conflict Resolution

iCloud wins. The calendar owner's changes take precedence. If the same event is modified on both sides between syncs, the iCloud version overwrites the Google version.

## Architecture

### Technical Stack

- **Language:** Swift 6.2 (strict concurrency)
- **Frameworks:** EventKit, SwiftData, ArgumentParser, Security (Keychain), CryptoKit
- **APIs:** Google Calendar REST API v3 via URLSession
- **Platform:** macOS 14+

### Components

```
CalSync CLI
  |
  +-- SyncEngine (ModelActor)
  |     |-- Phase 1: iCloud -> Google (forward sync)
  |     |-- Phase 2: Google -> iCloud (reverse sync)
  |     +-- Phase 3: Cleanup (deletions, stale mappings)
  |
  +-- iCloudService (Actor)
  |     +-- EventKit: read/write access to local calendar database
  |
  +-- GoogleCalendarService (Actor)
  |     +-- URLSession: REST API communication
  |
  +-- GoogleAuthService (Actor)
  |     +-- OAuth2 flow with local redirect server
  |     +-- Keychain token storage and refresh
  |
  +-- SwiftData Models
        +-- CalendarMapping: iCloud <-> Google calendar pairs
        +-- EventMapping: per-event sync state and checksums
```

## Data Models

### EventMapping (SwiftData)

```swift
@Model
final class EventMapping {
    @Attribute(.unique) var icloudUID: String
    var googleEventID: String?
    var calendarMappingID: String   // links to parent CalendarMapping.icloudIdentifier
    var lastSyncDate: Date
    var icloudChecksum: String?    // hash of iCloud event state at last sync
    var googleChecksum: String?    // hash of Google event state at last sync
    var syncDirection: String      // "icloud" or "google" — where the event originated
    var deletedOnIcloud: Bool      // event disappeared from iCloud
    var deletedOnGoogle: Bool      // event disappeared from Google
}
```

**Note on `icloudUID`:** For recurring events, EventKit's `calendarItemExternalIdentifier` is shared across all occurrences. To avoid uniqueness collisions, the UID is composed as `calendarItemExternalIdentifier + "|" + occurrenceDate` (ISO 8601 UTC). For non-recurring events, the occurrence date suffix is omitted.

### CalendarMapping (SwiftData)

```swift
@Model
final class CalendarMapping {
    @Attribute(.unique) var icloudIdentifier: String
    var googleCalendarID: String?
    var name: String
    var isEnabled: Bool
    var syncWindowPast: Int        // days to look back (default 7)
    var syncWindowFuture: Int      // days to look ahead (default 30)
    var autoCreateGoogleCalendar: Bool  // create target Google calendar on configure
}
```

### iCloudEvent (Sendable value type)

Existing fields plus:
- `attendees: [(name: String, status: EKParticipantStatus)]`
- `status: EKEventStatus`

### Checksum Fields

Both iCloud and Google checksums are SHA-256 hashes of the same semantic fields to ensure symmetry. Fields included:

- Title / summary
- Description / notes
- Location
- Start date (ISO 8601 UTC)
- End date (ISO 8601 UTC)
- All-day flag
- Event status (confirmed, tentative, cancelled)

**Not checksummed:** Attendees (RSVP status changes from other attendees would cause constant churn), recurrence rules (handled via occurrence-based UIDs).

All dates are normalized to ISO 8601 UTC before hashing to avoid false-positive changes from locale or time zone differences.

## Sync Engine Flow

### Phase 1: iCloud to Google (forward sync)

1. Fetch iCloud events for the configured sync window
2. For each event, compute current iCloud checksum
3. No existing mapping: create event on Google, store both checksums, set `syncDirection: "icloud"`
4. Mapping exists, iCloud checksum changed: update Google event, store new checksums
5. Mapping exists but no matching iCloud event: mark `deletedOnIcloud = true`, delete from Google

### Phase 2: Google to iCloud (reverse sync)

1. Fetch Google events for each mapped calendar
2. For each event with an existing mapping, compute current Google checksum
3. Google checksum changed AND iCloud checksum unchanged: push changes to iCloud via EventKit
4. Google checksum changed AND iCloud checksum also changed: iCloud wins, overwrite Google
5. Google event has no existing mapping: create in iCloud, store new EventMapping with `syncDirection: "google"` and both checksums
6. Event has `syncDirection: "google"` with no iCloud counterpart AND `deletedOnIcloud` is NOT set: create in iCloud via EventKit
7. For each EventMapping whose `googleEventID` is not found in fetched Google events: set `deletedOnGoogle = true`

**Important:** Step 6 checks the `deletedOnIcloud` flag set by Phase 1 to prevent resurrecting events that the iCloud calendar owner intentionally deleted.

### Phase 3: Cleanup

1. `deletedOnGoogle` + originated from Google: delete the iCloud event
2. `deletedOnGoogle` + originated from iCloud: recreate on Google (owner didn't delete it)
3. `deletedOnIcloud` + originated from Google: delete from Google (iCloud owner's deletion is authoritative, consistent with iCloud-wins)
4. Purge completed deletion mappings

## OAuth2 & Token Management

### Auth Flow

1. User runs `calsync auth` (one-time setup)
2. Local redirect server starts on port 8080
3. User opens the authorization URL in their browser
4. Google redirects back with auth code
5. Code is exchanged for access + refresh tokens
6. Both tokens and expiry timestamp stored in macOS Keychain (`com.calsync.google-oauth`)
7. Client ID and secret also stored in Keychain on first auth

### Token Refresh

- Before each sync, check if access token is expired
- If expired, use refresh token to obtain a new access token
- If refresh token is invalid, abort with a message to re-run `calsync auth`
- If a 401 is received mid-sync, attempt one token refresh and retry

### Google Cloud Project Setup (Manual Prerequisite)

1. Create a Google Cloud project
2. Enable the Google Calendar API
3. Create OAuth 2.0 Desktop credentials
4. Note the client ID and client secret for `calsync auth`

## CLI Commands

| Command | Description |
|---------|-------------|
| `calsync auth` | One-time Google OAuth setup, stores tokens in Keychain |
| `calsync list-calendars` | Shows available iCloud and Google calendars |
| `calsync configure <icloud-id>` | Maps an iCloud calendar to a Google calendar (auto-creates dedicated Google calendar by default) |
| `calsync sync` | Runs bidirectional sync (manual or launchd) |
| `calsync status` | Shows last sync time per calendar, errors from last run |
| `calsync install [--interval <minutes>]` | Sets up launchd scheduling (default 10 min) |
| `calsync uninstall` | Removes launchd scheduling |

## Scheduling

### launchd Integration

`calsync install` generates `~/Library/LaunchAgents/com.calsync.agent.plist`:
- Runs `calsync sync` on the configured interval
- Logs output to `~/Library/Logs/calsync.log`
- `calsync uninstall` removes the plist and unloads the agent

## Error Handling

- **Network failures:** Log error, skip event, don't update checksums so it retries next run. No retry loops within a single run.
- **EventKit permission denied:** Clear error message with instructions to grant Calendar access in System Settings > Privacy & Security > Calendars.
- **Shared calendar read-only:** If EventKit write-back fails due to permissions, log a warning, skip, and mark the mapping as read-only for future runs.
- **Token expiry mid-sync:** `GoogleCalendarService` handles 401 responses internally — attempts one token refresh and retries the request. If refresh fails, surfaces an auth error. This keeps auth concerns out of `SyncEngine`.
- **Stale mappings:** If a calendar mapping points to an iCloud calendar that no longer exists, log it and disable the mapping.

## Logging

Simple structured logging via `os.Logger` or plain file writes. stdout/stderr for manual runs, `~/Library/Logs/calsync.log` for launchd runs. No external logging framework.

## Implementation Notes

### Changes from existing code

The existing codebase was built for one-way (iCloud → Google) sync in a corporate context. Key changes required:

- **`EventMapping`:** Add `calendarMappingID`, split `checksum` into `icloudChecksum`/`googleChecksum`, add `syncDirection`, `deletedOnIcloud`, `deletedOnGoogle`
- **`CalendarMapping`:** Add `syncWindowPast`, `syncWindowFuture`, `autoCreateGoogleCalendar`
- **`iCloudEvent`:** Add `attendees` and `status` fields
- **`iCloudService`:** Add `createEvent(in:)`, `updateEvent(_:)`, `deleteEvent(_:)` methods for write-back
- **`GoogleCalendarService`:** Add `location`, `status`, `attendees` to `GoogleEvent` struct. Add 401/token-refresh interceptor.
- **`GoogleAuthService`:** Store tokens in Keychain instead of printing. Add token refresh flow.
- **`SyncEngine`:** Rewrite from one-way to three-phase bidirectional sync. Use configurable sync window with lookback.
- **`EKEvent+Checksum`:** Normalize dates to ISO 8601 UTC. Add `status` to checksum. Remove locale-dependent `Date.description`.
- **`configure` command:** Change from requiring both IDs to taking only `<icloud-id>` and auto-creating a dedicated Google calendar via `calendars.insert`.
- **CLI:** Add `status`, `install`, `uninstall` subcommands.

### Recurring events

EventKit's `events(matching:)` returns individual occurrences of recurring events, all sharing the same `calendarItemExternalIdentifier`. To handle this, `icloudUID` uses a composite key: `calendarItemExternalIdentifier + "|" + occurrenceStartDate` (ISO 8601 UTC). This ensures uniqueness per occurrence while maintaining traceability to the parent event.

## Future Considerations

- **Menubar app:** The architecture supports this cleanly. All logic is in the services/engine layer, not the CLI. A menubar app would be a different frontend calling the same components. Would require extracting core logic into a library target in `Package.swift` — straightforward refactor, not a design change.
- **Delta sync:** Google Calendar sync tokens to minimize API usage.
- **Recurring event editing:** Editing a single occurrence vs. all future occurrences of a recurring series. V1 treats each occurrence independently.
