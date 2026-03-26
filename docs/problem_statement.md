# CalSync Problem Statement

I use Google Calendar as my primary calendar app for managing my schedule. However,
family and friends share private iCloud calendars with me that Google Calendar cannot
subscribe to. These are private iCal subscriptions tied to iCloud accounts — not public
calendars.

Google Calendar supports the iCal format and public subscription URLs, but it cannot
receive invitations to private iCloud calendars or subscribe to private iCloud calendar
URLs. Apple Calendar / iCloud appears to be the only way to consume these privately
shared calendars.

Managing and reconciling two calendar apps is fraught with peril. What I want is a tool
that can bidirectionally sync specific Apple calendars with Google Calendar, enabling
Google Calendar as a "single pane of glass" for event management — including privately
shared Apple calendars that are otherwise inaccessible.

**Goal:** Bidirectional sync between private shared iCloud calendars and Google Calendar,
with iCloud as the authoritative source for conflict resolution.
