# Announcements (merged template + announcement)

Backend continues to send the same realtime payloads (`ANNOUNCEMENT`, `ANNOUNCEMENT_CLEAR`, `ANNOUNCEMENT_TRANSPORT`). No Flutter protocol changes were required for this merge.

Admin/API changes (repeatable push, `enabled`, `contentLockedUntil`) affect scheduling and CRUD only; the kiosk still applies local wall-clock duration from `durationSec` in the `ANNOUNCEMENT` payload.
