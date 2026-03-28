# CalSync

Bidirectional sync between private shared iCloud calendars and Google Calendar.

---

## The Problem

Google Calendar can't subscribe to privately shared iCloud calendars. Apple Calendar is the only app that can receive these invitations — but if Google Calendar is your primary calendar, you're stuck managing two apps and mentally reconciling two views of your schedule.

CalSync bridges the gap. It syncs specific iCloud calendars to Google Calendar and keeps them in sync in both directions, so Google Calendar becomes your single view of everything.

## How It Works

CalSync runs as a background agent on your Mac, syncing on a schedule you control (default: every 10 minutes). Each sync runs three phases:

1. **iCloud → Google** — new and changed iCloud events are pushed to Google Calendar
2. **Google → iCloud** — new and changed Google events are pushed back to iCloud
3. **Deletion arbitration** — deletions on either side are propagated correctly

When the same event is changed on both sides between syncs, iCloud wins.

## Requirements

- macOS 14+
- Swift 6.2
- A Google account with a Google Cloud project (for API access — see [setup guide](docs/user-guide.md))

## Installation

```bash
git clone https://github.com/bnaylor/calsync
cd calsync
swift build -c release
cp .build/release/CalSync /usr/local/bin/calsync
```

## Setup

**1. Authenticate with Google**

Create OAuth credentials in the [Google Cloud Console](https://console.cloud.google.com/) (see the [user guide](docs/user-guide.md) for step-by-step instructions), then:

```bash
calsync auth <client-id> <client-secret>
```

**2. Find your iCloud calendar**

```bash
calsync list-calendars
# Family [iCloud] (Identifier: ABC123-DEF456-...)
```

**3. Configure a sync**

```bash
calsync configure ABC123-DEF456
```

This creates a new Google Calendar and links it to the iCloud calendar.

**4. Run a sync**

```bash
calsync sync
```

**5. Set up automatic syncing**

```bash
calsync install           # syncs every 10 minutes
calsync install --interval 5   # or every 5 minutes
```

Logs go to `~/Library/Logs/calsync.log`.

## Commands

| Command | Description |
|---------|-------------|
| `calsync auth <id> <secret>` | One-time Google OAuth setup |
| `calsync list-calendars` | List available iCloud calendars |
| `calsync configure <icloud-id>` | Link an iCloud calendar to a new Google Calendar |
| `calsync sync` | Run a bidirectional sync |
| `calsync status` | Show sync status and last sync time |
| `calsync install [--interval <min>]` | Schedule automatic sync via launchd |
| `calsync uninstall` | Remove automatic sync |

## Menu Bar App (optional)

A SwiftUI menu bar app is included for at-a-glance status and manual sync:

```bash
./CalSyncApp/run.sh
```

Click the calendar icon in your menu bar to see configured calendars and trigger a sync. Open Settings to manage calendar mappings and Google account authentication.

> **Note:** The menu bar app is a development build helper. For a proper install, an Xcode project wrapper is needed.

## Architecture

CalSync is a Swift Package with two targets:

- **`CalSyncLib`** — the core library: SwiftData models, sync engine, service layer, EventKit integration, Google Calendar API client
- **`CalSync`** — a thin CLI executable built on ArgumentParser

The sync engine tracks events using dual checksums (one per side) stored in a local SwiftData database, enabling it to detect which side changed without relying on modification timestamps.

## Caveats

- **Sync window:** Only events within a configurable window (default: 7 days past, 30 days future) are synced. Older events are not touched.
- **Conflict resolution:** iCloud always wins when both sides change the same event between syncs.
- **Google Calendar quota:** The Google Calendar API has daily request limits. For most personal use this is not a concern.
- **Early software:** Edge cases around network failures and partial syncs are still being hardened.

## License

MIT
