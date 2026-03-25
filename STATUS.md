# CalSync Project Status

## Current Progress
We have successfully scaffolded the core architecture for a native macOS CLI tool to sync iCloud calendars to Google Calendar.

### Completed
- **Project Initialization:** Created a Swift 6.2 executable package (`CalSync`).
- **Architecture Design:** Documented in `docs/design.md`, focusing on security (preventing Google -> iCloud leakage) and performance (using native `EventKit`).
- **Data Models:** Implemented `EventMapping` and `CalendarMapping` using **SwiftData** for local state persistence.
- **iCloud Integration:** Created `iCloudService` to interface with the macOS `EventKit` database.
- **Sync Engine:** Implemented `SyncEngine` with:
  - One-way sync logic (iCloud to Google).
  - Stable checksum-based change detection (`SHA-256`) to minimize API calls.
  - Swift concurrency (`actor` and `@ModelActor`) for thread safety.
- **CLI Interface:** Added subcommands for `sync`, `list-calendars`, and `configure` using `swift-argument-parser`.
- **Testing:** Scaffolded a basic test suite using the **Swift Testing** framework.

### In Progress / Blocked
- **Build Blocker:** Currently unable to compile or run binaries due to 'Santa' security interception on the corporate laptop.
- **Google API Integration:** `GoogleCalendarService` is scaffolded but requires full REST implementation (Update/Delete) and OAuth2 flow.

## Next Steps
Once the build system is accessible:

1.  **Verify Build:** Successfully run `swift build` and approve the resulting binaries in 'Santa'.
2.  **OAuth2 Implementation:** Build a small local redirect server to handle the Google Calendar authorization flow and securely store tokens.
3.  **Refine Sync Engine:**
    - Implement event deletion (removing Google events if the iCloud source is gone).
    - Add batching for API requests to improve performance.
4.  **Integration Testing:** Run the tool against real iCloud calendars and verify the "Single Pane of Glass" view in Google Calendar.
5.  **P1 Implementation (Optional):** Explore strictly-filtered two-way sync as discussed in the design doc.

---
*Last Updated: Tuesday, March 24, 2026*
