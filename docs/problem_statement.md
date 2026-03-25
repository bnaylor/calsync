# Calsync Problem Statement

I have specific calendars that have been shared with me by Apple ecosystem users which
are private ical subscriptions tied to iCloud accounts.  They are not public calendars.

My primary calendar application for both home and work is Google Calendar, which supports
the iCal format and publication urls and such, but it does not look like Google Calendar
is capable of receiving invitations to private calendars or subscribing to icloud private
calendar urls.

Google does not allow the use of iCloud software / accounts on corporate devices in order
to prevent accidental data exfiltration / leakage.  It allows for publishing calendars but
only with most of the details automatically filed off  (entries just say "busy").  I accept
this, and do not seek to publish my work calendar details beyond what is already possible.

It seems like Apple Calendar / iCloud is the only viable way to consume these privately shared
calendars.  Managing and reconciling two calendar apps is fraught with peril.

What I would like to do is create a tool, scripts, processes, or something of that nature
that can locally sync specific *Apple* calendars from iCal <> Google Calendar.

P0: One-way, read-only sync of Apple calendar to Google
P1: Allow editing of Apple calendar on Google calendar, sync changes back to Apple

This would enable Google Calendar as a "single pane of glass" for event management, including
privately shared Apple calendars that are currently not accessible.




