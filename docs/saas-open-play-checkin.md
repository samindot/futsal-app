# FutsalKita SaaS / Open Play / Booth Check-in foundation

This is the first incremental foundation for the venue SaaS direction. It does not replace the existing team-vs-team matchmaking flow.

## Product model

- **Booking** reserves the actual court/time. Existing overlap protection remains the source of truth.
- **Team matchmaking** remains team-vs-team and links to a booking.
- **Open Play** is a separate session linked to one existing booking. People join as individual accounts; the host can calculate actual cost sharing after the game. FutsalKita does not require participants to pay each other through the platform.
- **Check-in Booth** is a venue staff-operated tablet/browser page. A participant creates a short-lived QR token in the player app; the booth redeems it. Only active staff belonging to the session's venue can redeem it.
- **Reputation** should derive from server-recorded check-ins and session history, not from merely joining. No-show rules and correction workflows should be added before displaying reputation scores.

## Migration 007

File: `supabase/migrations/007_venue_open_play_checkin_foundation.sql`

It adds:
- `venues` and `venue_members` for tenant boundaries;
- `venue_id` on fields and bookings, backfilled into a legacy venue;
- `open_play_sessions` and `open_play_participants`;
- one-time, two-minute check-in tokens stored as SHA-256 hashes;
- check-in events and security-definer RPCs for venue creation, Open Play creation/join/leave, token creation, and booth redemption;
- RLS policies for venue/session visibility.

Apply the SQL manually in Supabase SQL Editor. This branch only contains the migration at this stage; no live database was modified by GitHub commits.

## Important MVP limits

- The existing venue is assigned to a legacy venue row. Rename/update its location and assign actual venue members before using the booth.
- Existing global admin permissions and field-management UI are not yet converted to venue-scoped SaaS permissions.
- The first check-in flow covers Open Play participants. Individual roster/check-in for every member of a team-vs-team session is a later step.
- The booth frontend and player-side QR screen are next, after the migration has been applied and validated.
- No payment gateway or individual participant debt ledger is introduced.
