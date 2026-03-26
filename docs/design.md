# CalSync Design Document

## Overview

CalSync is a macOS command-line utility that bidirectionally syncs private iCloud calendars with Google Calendar. It enables Google Calendar as a "single pane of glass" for event management, including privately shared Apple calendars that Google Calendar cannot natively subscribe to.

For the full design specification, see [`docs/superpowers/specs/2026-03-25-home-pivot-design.md`](superpowers/specs/2026-03-25-home-pivot-design.md).

## Architecture

### Technical Stack
- **Language:** Swift 6.2 (Strict Concurrency)
- **Frameworks:**
  - **EventKit:** Native macOS access to the local Calendar database (iCloud).
  - **SwiftData:** Local persistence for event mapping and state tracking.
  - **ArgumentParser:** CLI command and option management.
- **APIs:** Google Calendar REST API (v3) via `URLSession`.
- **Credential Storage:** macOS Keychain via `KeychainService`.
- **Scheduling:** `launchd` for automatic periodic sync.

### Components

#### 1. Services Layer
- **`iCloudService` (Actor):** Wraps `EventKit`. Handles permission requests and fetches events/calendars from the system's local calendar store. Actor isolation ensures thread-safe access to the underlying `EKEventStore`.
- **`GoogleCalendarService` (Actor):** Manages REST communication with Google Calendar API. Handles event CRUD operations with automatic 401 retry via token refresh.
- **`GoogleAuthService`:** Manages OAuth2 authentication with Keychain-backed token persistence. Handles the local redirect server for authorization and automatic token refresh.
- **`KeychainService`:** Secure storage for OAuth tokens using the macOS Keychain.

#### 2. Data Layer (SwiftData)
- **`CalendarMapping`:** Stores the link between an iCloud calendar identifier and a Google Calendar ID. Tracks whether sync is enabled for that specific pair.
- **`EventMapping`:** The core of the sync engine. Maps an `icloudUID` to a `googleEventID`. Stores dual checksums — an `icloudChecksum` and a `googleChecksum` — to detect changes on either side. Uses shared checksum computation with ISO 8601 date normalization for cross-platform consistency.

#### 3. Sync Engine
- **`SyncEngine` (ModelActor):** Orchestrates bidirectional sync in three phases:
  1. **iCloud Detection:** Fetches iCloud events, compares checksums against stored `icloudChecksum` to find new, changed, or deleted iCloud events. Pushes changes to Google.
  2. **Google Detection:** Fetches Google events, compares checksums against stored `googleChecksum` to find new, changed, or deleted Google events. Pushes changes to iCloud.
  3. **Deletion Arbitration:** Handles deletions detected on either side. When an event is deleted from one calendar, the corresponding event is removed from the other.
- **Conflict Resolution:** iCloud wins. If both sides changed the same event since the last sync, the iCloud version is applied to Google.

## Workflow
1. **Configuration:** User runs `calsync configure` to set up Google OAuth and map an iCloud calendar to a target Google Calendar (auto-created if it doesn't exist).
2. **Sync:** User runs `calsync sync`.
   - Engine fetches events from both iCloud and Google for the configured window.
   - Engine reconciles state using the SwiftData store and dual checksums.
   - Engine pushes necessary changes in both directions.
3. **Status:** User runs `calsync status` to view sync state.
4. **Scheduling:** User runs `calsync install` / `calsync uninstall` to manage launchd-based automatic sync.

## Local Execution
CalSync runs entirely on the local Mac. By using `EventKit`, Keychain, and local SwiftData, it avoids intermediate cloud services or third-party servers that would otherwise handle sensitive tokens or event data.
