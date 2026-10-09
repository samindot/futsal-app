-- Futsal app initial schema
-- Run once in Supabase SQL Editor for the new project.
begin;

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  phone text,
  skill_level text not null default 'beginner'
    check (skill_level in ('beginner','intermediate','advanced','any')),
  role text not null default 'player'
    check (role in ('player','admin')),
  created_at timestamptz not null default now()
);

create table if not exists public.fields (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  location text,
  hourly_rate numeric(12,2) not null default 0 check (hourly_rate >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.bookings (
  id uuid primary key default gen_random_uuid(),
  field_id uuid not null references public.fields(id),
  booking_date date not null,
  start_time time not null,
  duration_hours integer not null check (duration_hours between 1 and 8),
  customer_name text not null,
  amount_paid numeric(12,2) not null default 0 check (amount_paid >= 0),
  notes text,
  status text not null default 'confirmed'
    check (status in ('pending','confirmed','cancelled','completed')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint booking_end_within_day check (
    start_time + make_interval(hours => duration_hours) <= time '24:00'
  )
);

create index if not exists bookings_date_field_idx
  on public.bookings (booking_date, field_id, start_time)
  where status <> 'cancelled';

create table if not exists public.matchmaking_sessions (
  id uuid primary key default gen_random_uuid(),
  host_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  venue text not null,
  session_date date not null,
  start_time time not null,
  duration_hours integer not null default 2 check (duration_hours between 1 and 8),
  skill_level text not null default 'any'
    check (skill_level in ('beginner','intermediate','advanced','any')),
  max_players integer not null default 10 check (max_players between 2 and 30),
  notes text,
  status text not null default 'open'
    check (status in ('open','full','cancelled','completed')),
  created_at timestamptz not null default now()
);

create table if not exists public.matchmaking_players (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.matchmaking_sessions(id) on delete cascade,
  player_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'joined'
    check (status in ('joined','waitlist','cancelled')),
  created_at timestamptz not null default now(),
  unique (session_id, player_id)
);

create index if not exists matchmaking_sessions_date_idx
  on public.matchmaking_sessions (session_date, start_time)
  where status = 'open';

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1)))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid()) and p.role = 'admin'
  );
$$;

create or replace function public.create_booking(
  p_field_id uuid,
  p_date date,
  p_start time,
  p_duration integer,
  p_amount_paid numeric default 0,
  p_notes text default null,
  p_customer_name text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_booking_id uuid;
  v_customer_name text;
begin
  if (select auth.uid()) is null or not public.is_admin() then
    raise exception 'Only authenticated admins can create bookings';
  end if;

  if p_duration is null or p_duration < 1 or p_duration > 8 then
    raise exception 'Duration must be between 1 and 8 hours';
  end if;

  v_customer_name := nullif(trim(coalesce(p_customer_name, '')), '');
  if v_customer_name is null then
    raise exception 'Customer name is required';
  end if;

  perform 1 from public.fields where id = p_field_id and is_active = true;
  if not found then
    raise exception 'Field not found or inactive';
  end if;

  if exists (
    select 1
    from public.bookings b
    where b.field_id = p_field_id
      and b.booking_date = p_date
      and b.status <> 'cancelled'
      and b.start_time < p_start + make_interval(hours => p_duration)
      and b.start_time + make_interval(hours => b.duration_hours) > p_start
  ) then
    raise exception 'This time slot overlaps an existing booking';
  end if;

  insert into public.bookings (
    field_id, booking_date, start_time, duration_hours,
    customer_name, amount_paid, notes, created_by
  ) values (
    p_field_id, p_date, p_start, p_duration,
    v_customer_name, greatest(coalesce(p_amount_paid, 0), 0), p_notes, (select auth.uid())
  ) returning id into v_booking_id;

  return v_booking_id;
end;
$$;

alter table public.profiles enable row level security;
alter table public.fields enable row level security;
alter table public.bookings enable row level security;
alter table public.matchmaking_sessions enable row level security;
alter table public.matchmaking_players enable row level security;

drop policy if exists "Profiles readable by self or admin" on public.profiles;
create policy "Profiles readable by self or admin"
  on public.profiles for select to authenticated
  using (id = (select auth.uid()) or public.is_admin());

drop policy if exists "Users update own profile" on public.profiles;
create policy "Users update own profile"
  on public.profiles for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()) and role = 'player');

drop policy if exists "Active fields are public" on public.fields;
create policy "Active fields are public"
  on public.fields for select to anon, authenticated
  using (is_active = true or public.is_admin());

drop policy if exists "Admins manage fields" on public.fields;
create policy "Admins manage fields"
  on public.fields for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "Bookings visible to creator or admin" on public.bookings;
create policy "Bookings visible to creator or admin"
  on public.bookings for select to authenticated
  using (created_by = (select auth.uid()) or public.is_admin());

drop policy if exists "Admins update bookings" on public.bookings;
create policy "Admins update bookings"
  on public.bookings for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "Open matchmaking sessions are public" on public.matchmaking_sessions;
create policy "Open matchmaking sessions are public"
  on public.matchmaking_sessions for select to anon, authenticated
  using (status = 'open' or host_id = (select auth.uid()) or public.is_admin());

drop policy if exists "Authenticated users create sessions" on public.matchmaking_sessions;
create policy "Authenticated users create sessions"
  on public.matchmaking_sessions for insert to authenticated
  with check (host_id = (select auth.uid()));

drop policy if exists "Hosts or admins update sessions" on public.matchmaking_sessions;
create policy "Hosts or admins update sessions"
  on public.matchmaking_sessions for update to authenticated
  using (host_id = (select auth.uid()) or public.is_admin())
  with check (host_id = (select auth.uid()) or public.is_admin());

drop policy if exists "Players visible to self, host, or admin" on public.matchmaking_players;
create policy "Players visible to self, host, or admin"
  on public.matchmaking_players for select to authenticated
  using (
    player_id = (select auth.uid())
    or public.is_admin()
    or exists (
      select 1 from public.matchmaking_sessions s
      where s.id = session_id and s.host_id = (select auth.uid())
    )
  );

drop policy if exists "Users join as themselves" on public.matchmaking_players;
create policy "Users join as themselves"
  on public.matchmaking_players for insert to authenticated
  with check (player_id = (select auth.uid()));

drop policy if exists "Users cancel own participation" on public.matchmaking_players;
create policy "Users cancel own participation"
  on public.matchmaking_players for update to authenticated
  using (player_id = (select auth.uid()) or public.is_admin())
  with check (player_id = (select auth.uid()) or public.is_admin());

grant execute on function public.is_admin() to anon, authenticated;
grant execute on function public.create_booking(uuid, date, time, integer, numeric, text, text) to authenticated;

commit;
