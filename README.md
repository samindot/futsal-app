# FutsalKita — Booking Lapangan & Matchmaking

A static HTML/ES-module frontend deployed on Cloudflare Pages, using Supabase Auth and Postgres.

## Features implemented in this branch

- Public landing page with date-based court availability; public RPCs expose no customer names or payment data.
- Authenticated booking requests with overlap prevention and a pending status for admin confirmation.
- Email/password registration and login with a safe return path after login.
- Admin booking calendar: create admin bookings, edit customer/payment details, confirm, complete, or cancel bookings.
- Open-match discovery with skill level, venue, schedule, capacity, and join/leave actions.
- Authenticated players can create sessions; the host counts toward session capacity and can cancel their own session.
- Row Level Security and security-definer RPCs for booking creation, public availability, public session counts, and capacity-checked participation changes.

## 1. Set up Supabase

1. Create the new Supabase project.
2. Open **SQL Editor** and run the full contents of `supabase/migrations/001_initial_schema.sql` once.
3. Open the app and use **Login / Daftar** to create your account. Complete email confirmation if Supabase requires it.
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

The browser client in `js/supabase.js` contains only the project URL and publishable key. Never put a Supabase secret key or `service_role` key in frontend code or GitHub.

## 2. Cloudflare Pages

For this plain HTML/ES-module project:

- Connect repository: `samindot/futsal-app`.
- Production branch: `main` after the PR is reviewed and merged.
- Build command: leave blank.
- Build output directory: `.` (repository root).
- No framework preset is required.

The working branch is `rebuild/supabase-foundation`. The draft PR is available at https://github.com/samindot/futsal-app/pull/1. Do not promote it to production until the migration has been applied and the end-to-end checklist below passes.

## 3. Smoke-test checklist

- [ ] SQL migration runs successfully in the new project.
- [ ] Register a player account and confirm email if required.
- [ ] Promote the intended admin account using the SQL above.
- [ ] Insert the real fields and prices.
- [ ] Public landing page shows the fields and availability for a selected date.
- [ ] A logged-in player can request a booking; its status starts as pending.
- [ ] Admin can confirm/cancel a booking and update payment details.
- [ ] Overlapping booking requests are rejected by the database.
- [ ] Player can create an open-match session, join, and leave.
- [ ] Session capacity includes its host and cannot be bypassed through direct table writes.
- [ ] Non-admin users cannot open the admin booking calendar.
- [ ] Test on mobile and desktop.

## Current boundaries

- Booking requests require an account and remain pending until an admin confirms them.
- Payment tracking is a simple amount-paid field, not a payment gateway.
- Matchmaking is a player-organized session board, not an automated team-balancing algorithm or chat system.
- The migration and frontend have not yet been tested against the live Supabase project. Apply the migration and complete the checklist before using real bookings.
