# CalSync Project Status

## Current State
Personal-use bidirectional sync tool between private shared iCloud calendars and Google Calendar. Pivoted from a corporate use case to home use.

### Completed
- **Project Setup:** Swift 6.2 executable package (`CalSync`) with `CalSyncLib` library.
- **SwiftData Models:** `EventMapping` and `CalendarMapping` with dual checksums (`icloudChecksum` / `googleChecksum`) for bidirectional change detection.
- **Shared Checksum:** Cross-platform checksum computation with ISO 8601 date normalization for consistent comparison between iCloud and Google events.
- **Service Protocols with Mocks:** Protocol-based service layer enabling unit testing without live API calls.
- **KeychainService:** Secure token storage using the macOS Keychain.
- **GoogleAuthService:** OAuth2 flow with Keychain-backed token persistence and automatic refresh.
- **GoogleCalendarService:** Full CRUD operations against Google Calendar API with automatic 401 retry on token expiry.
- **iCloudService:** EventKit integration for reading and writing iCloud calendar events.
- **Three-Phase Bidirectional SyncEngine:**
  1. iCloud change detection and push to Google.
  2. Google change detection and push to iCloud.
  3. Deletion arbitration across both sides.
  - iCloud-wins conflict resolution.
- **CLI Commands:**
  - `calsync status` — view sync state.
  - `calsync install` / `calsync uninstall` — manage launchd scheduling.
  - `calsync configure` — Google OAuth setup with auto-create Google Calendar.
  - `calsync sync` — run bidirectional sync.
  - `calsync list-calendars` — show available iCloud calendars.
- **Testing:** Unit test suite using the Swift Testing framework with mock services.
- **Menu Bar App:** SwiftUI menu bar app (`CalSyncApp`) with popover status view, manual sync trigger, and Settings window for calendar mapping and Google account management. Runs via `./CalSyncApp/run.sh`.
- **Documentation:** User guide, README, and updated design docs.
- **Production:** CLI actively syncing real iCloud and Google calendars.

### Remaining
- **Menu Bar App — Auth UX:** OAuth flow has no in-app feedback while waiting for the browser redirect; re-auth requires dropping to the CLI.
- **Menu Bar App — Focus/Polish:** Popover focus, dismiss-on-outside-click, and Settings window activation have rough edges.
- **Menu Bar App — Xcode Project:** `run.sh` dev launcher works but a proper Xcode project is needed for distribution.
- **Edge Case Hardening:** Handle network failures, partial sync recovery, and API rate limits.
- **Title/Description Edit Support:** Detect and sync edits to event titles and descriptions (currently checksum covers time/date changes).

---
*Last Updated: Friday, March 27, 2026*
