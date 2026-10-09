# Futsal Booking + Matchmaking

Static frontend hosted on Cloudflare Pages; Supabase provides Auth and Postgres.

## Supabase setup

1. Create a Supabase project.
2. Open **SQL Editor** and run `supabase/migrations/001_initial_schema.sql`.
3. In **Authentication → Users**, create your admin user (email/password).
4. In SQL Editor, promote that account to admin by replacing the email below:

```sql
update public.profiles p
set role = 'admin'
from auth.users u
where p.id = u.id
  and u.email = 'YOUR_ADMIN_EMAIL';
```

5. Add one or more courts in SQL Editor (replace names, locations, and rates):

```sql
insert into public.fields (name, location, hourly_rate)
values
  ('Court 1', 'Your venue', 150000),
  ('Court 2', 'Your venue', 150000);
```

The frontend client in `js/supabase.js` uses only the project URL and publishable key. Never put a Supabase secret or `service_role` key in frontend code or GitHub.

## Current database model

- `profiles`: player profile and role.
- `fields`: courts/fields and hourly rate.
- `bookings`: admin-created bookings; overlapping active bookings are rejected by the database function.
- `matchmaking_sessions`: player-created open-play sessions.
- `matchmaking_players`: participation in matchmaking sessions.

Row Level Security is enabled. Create and test user accounts before opening the app publicly. The initial migration is the database foundation; the existing calendar UI still needs to be aligned with this schema, and the matchmaking UI/API is a subsequent implementation step.

## Cloudflare Pages

For this plain HTML/ES-module project, connect the GitHub repository in Cloudflare Pages. Use the root directory, no build command, and `/` as the output directory. Deploy the working branch only after the Supabase migration has been applied and the frontend flows have been tested.
