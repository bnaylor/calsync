# CalSync User Guide

CalSync syncs private shared iCloud calendars to Google Calendar, giving you a single place to see all your events. It supports bidirectional sync: changes on either side are reflected on the other.

## Prerequisites

- macOS 14+
- Swift 6.2 toolchain
- A Google account
- iCloud calendars shared with you (visible in Apple Calendar)

## 1. Google Cloud Project Setup

CalSync uses the Google Calendar API, which requires a Google Cloud project with OAuth credentials. This is a one-time setup.

### Create the project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Click the project dropdown at the top and select **New Project**
3. Name it something like "CalSync" and click **Create**
4. Make sure the new project is selected in the dropdown

### Enable the Google Calendar API

1. Go to **APIs & Services > Library**
2. Search for "Google Calendar API"
3. Click it and then click **Enable**

### Create OAuth credentials

1. Go to **APIs & Services > Credentials**
2. Click **Create Credentials > OAuth client ID**
3. If prompted, configure the consent screen first:
   - Choose **External** user type
   - Fill in the app name ("CalSync") and your email
   - Add the scope `https://www.googleapis.com/auth/calendar`
   - Add your Google account as a test user
   - Save and return to Credentials
4. For application type, select **Desktop app**
5. Name it "CalSync" and click **Create**
6. Note the **Client ID** and **Client Secret** — you'll need these next

## 2. Build CalSync

```bash
git clone <repo-url> calsync
cd calsync
swift build
```

The binary is at `.build/debug/CalSync`. You can copy it somewhere on your PATH:

```bash
cp .build/debug/CalSync /usr/local/bin/calsync
```

## 3. Grant Calendar Access

The first time CalSync accesses your calendars, macOS will prompt you to grant Calendar access. You can also grant it in advance:

**System Settings > Privacy & Security > Calendars** — enable access for CalSync (or Terminal, if running from the command line).

## 4. Authenticate with Google

Run the auth command with your Client ID and Client Secret from step 1:

```bash
calsync auth <client-id> <client-secret>
```

This will:
1. Print a URL — open it in your browser
2. Sign in with your Google account and authorize CalSync
3. Redirect back to `localhost:8080` to complete the flow
4. Store your tokens securely in the macOS Keychain

You only need to do this once. CalSync automatically refreshes expired tokens.

## 5. List Available Calendars

See which iCloud calendars are available to sync:

```bash
calsync list-calendars
```

Output looks like:

```
Found 3 iCloud calendars:
- Family [iCloud] (Identifier: ABC123-DEF456-...)
- Work [iCloud] (Identifier: GHI789-JKL012-...)
- Book Club [Other] (Identifier: MNO345-PQR678-...)
```

Note the identifier of the calendar you want to sync.

## 6. Configure a Calendar

Link an iCloud calendar to Google Calendar. This creates a new Google Calendar automatically:

```bash
calsync configure <icloud-identifier>
```

Options:
- `--name <name>` — custom name for the Google Calendar (defaults to the iCloud calendar name)
- `--past <days>` — how many days back to sync (default: 7)
- `--future <days>` — how many days ahead to sync (default: 30)

Example:

```bash
calsync configure ABC123-DEF456 --name "Family (synced)" --past 14 --future 60
```

Repeat for each calendar you want to sync.

## 7. Run a Sync

Manually trigger a sync:

```bash
calsync sync
```

This runs the full three-phase sync:
1. Detects iCloud changes and pushes them to Google
2. Detects Google changes and pushes them to iCloud
3. Handles deletions on either side

**Conflict resolution:** If the same event is modified on both sides between syncs, the iCloud version wins.

## 8. Set Up Automatic Sync

Install a launchd agent to sync on a schedule:

```bash
calsync install
```

Options:
- `--interval <minutes>` — sync frequency (default: 10)

Example:

```bash
calsync install --interval 5
```

This creates `~/Library/LaunchAgents/com.calsync.agent.plist` and starts syncing immediately. Logs go to `~/Library/Logs/calsync.log`.

To remove automatic syncing:

```bash
calsync uninstall
```

## 9. Check Status

See what's configured and when the last sync ran:

```bash
calsync status
```

Output looks like:

```
Family (synced) [enabled]
  iCloud ID: ABC123-DEF456-...
  Google ID: abc123@group.calendar.google.com
  Window: -7 to +30 days
  Events tracked: 42
  Last sync: Mar 25, 2026 at 3:15 PM
```

## Command Reference

| Command | Description |
|---------|-------------|
| `calsync auth <client-id> <client-secret>` | One-time Google OAuth setup |
| `calsync list-calendars` | Show available iCloud calendars |
| `calsync configure <icloud-id>` | Map an iCloud calendar to a new Google Calendar |
| `calsync sync` | Run bidirectional sync |
| `calsync status` | Show sync status for configured calendars |
| `calsync install [--interval <min>]` | Set up automatic sync via launchd |
| `calsync uninstall` | Remove automatic sync |

## Troubleshooting

**"Calendar access denied"** — Grant Calendar access in System Settings > Privacy & Security > Calendars.

**"Authentication required"** — Re-run `calsync auth` with your credentials.

**"Token refresh failed"** — Your refresh token may have expired (Google revokes tokens for apps in "Testing" mode after 7 days). Re-run `calsync auth`.

**Events not syncing** — Check `calsync status` to verify the calendar is configured and enabled. Check `~/Library/Logs/calsync.log` for errors if using automatic sync.
