# FutsalKita — Booking Lapangan & Matchmaking

A static HTML/ES-module frontend deployed on Cloudflare Pages, using Supabase Auth and Postgres.

## Features implemented in this branch

- Public landing page with date-based court availability (only safe availability fields are exposed publicly).
- Email/password registration and login.
- Admin booking calendar with create booking, update customer/payment details, and change booking status.
- Overlap checks for bookings in the database, including a transaction-level lock to reduce race conditions.
- Public open-match discovery with level, venue, time, capacity, and join/leave actions.
- Session creation for authenticated players; session creator counts toward capacity.
- Row Level Security policies and security-definer RPCs for public availability and safe matchmaking counts.

## 1. Set up Supabase

1. Create the new Supabase project.
2. Open **SQL Editor** and run the full contents of `supabase/migrations/001_initial_schema.sql` once.
3. Open the deployed app (or run it locally on a static HTTP server) and use **Login / Daftar** to create your account. Complete email confirmation if Supabase requires it.
4. In **Supabase → SQL Editor**, promote your account to admin by replacing the email below:

```sql
update public.profiles p
set role = 'admin'
from auth.users u
where p.id = u.id
  and lower(u.email) = lower('YOUR_ADMIN_EMAIL');
```

5. Add the actual courts, venue names, and hourly rates. Replace the sample data:

```sql
insert into public.fields (name, location, hourly_rate)
values
  ('Court 1', 'Your venue address', 150000),
  ('Court 2', 'Your venue address', 150000);
```

If you need to change the sample courts later, update or delete the rows in `public.fields` through SQL Editor.

The browser client in `js/supabase.js` contains only the project URL and publishable key. Never put a Supabase secret key or `service_role` key in frontend code or GitHub.

## 2. Cloudflare Pages

For this plain HTML/ES-module project:

- Connect repository: `samindot/futsal-app`.
- Production branch: `main` after the PR is reviewed and merged.
- Build command: leave blank.
- Build output directory: `/` (repository root).
- No framework preset is required.

The working branch is `rebuild/supabase-foundation`. The draft PR is available at https://github.com/samindot/futsal-app/pull/1. Do not promote it to production until the SQL migration has been applied and the end-to-end checklist below passes.

## 3. Smoke-test checklist

- [ ] SQL migration runs successfully in the new project.
- [ ] Register a player account and confirm email if required.
- [ ] Promote the intended admin account using the SQL above.
- [ ] Insert the real fields and prices.
- [ ] Public landing page shows the fields and availability for a selected date.
- [ ] Admin can create a booking and overlapping booking attempts are rejected.
- [ ] Admin can update payment amount/status and cancel a booking.
- [ ] Player can create an open-match session, join, and leave.
- [ ] Session capacity includes its host and does not exceed the configured maximum.
- [ ] Non-admin users cannot open the admin booking calendar.
- [ ] Test on mobile viewport and desktop.

## Notes and current boundaries

- Court reservations are currently created by admins; public users can see availability but do not yet submit a reservation request themselves.
- Payment tracking is a simple amount-paid field, not a payment gateway.
- Matchmaking is a player-organized session board, not an automated team-balancing algorithm or chat system.
- This branch has not been tested against the live Supabase project yet. Apply the migration and complete the checklist before using real bookings.
