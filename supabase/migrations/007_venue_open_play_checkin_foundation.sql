-- FutsalKita multi-venue foundation + Open Play + verified booth check-in.
-- Apply manually in Supabase SQL Editor after reviewing. This migration does not process payments.
begin;

create extension if not exists pgcrypto;

-- Multi-tenant venue layer. Existing fields/bookings are assigned to a legacy venue.
create table if not exists public.venues (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 2 and 120),
  slug text not null unique,
  location text,
  owner_id uuid references auth.users(id) on delete set null,
  status text not null default 'active' check (status in ('active','suspended')),
  timezone text not null default 'Asia/Jakarta',
  created_at timestamptz not null default now()
);

create table if not exists public.venue_members (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','manager','staff')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (venue_id, user_id)
);
create index if not exists venue_members_user_idx on public.venue_members(user_id, is_active);
create index if not exists venue_members_venue_idx on public.venue_members(venue_id, role) where is_active;

alter table public.fields add column if not exists venue_id uuid references public.venues(id);
alter table public.bookings add column if not exists venue_id uuid references public.venues(id);

insert into public.venues(name, slug, location, owner_id)
values (
  'FutsalKita Legacy Venue',
  'futsalkita-legacy',
  'Venue awal FutsalKita — perbarui nama dan lokasi sebelum dipakai publik',
  (select p.id from public.profiles p where p.role = 'admin' order by p.created_at limit 1)
)
on conflict (slug) do nothing;

update public.fields f
set venue_id = v.id
from public.venues v
where v.slug = 'futsalkita-legacy' and f.venue_id is null;

update public.bookings b
set venue_id = f.venue_id
from public.fields f
where f.id = b.field_id and b.venue_id is null;

insert into public.venue_members(venue_id, user_id, role)
select v.id, p.id, 'owner'
from public.venues v
join public.profiles p on p.role = 'admin'
where v.slug = 'futsalkita-legacy'
on conflict (venue_id, user_id) do nothing;

create index if not exists fields_venue_idx on public.fields(venue_id, is_active);
create index if not exists bookings_venue_date_idx on public.bookings(venue_id, booking_date, start_time);

-- A field must belong to a venue after legacy backfill. Existing booking rows inherit it.
alter table public.fields alter column venue_id set not null;
alter table public.bookings alter column venue_id set not null;

-- Open Play is intentionally separate from team-vs-team matchmaking.
create table if not exists public.open_play_sessions (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues(id),
  booking_id uuid not null references public.bookings(id) on delete cascade,
  host_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (length(trim(title)) between 2 and 120),
  max_players integer not null check (max_players between 2 and 30),
  skill_level text not null default 'any'
    check (skill_level in ('beginner','intermediate','advanced','any')),
  notes text,
  status text not null default 'open'
    check (status in ('open','full','cancelled','completed')),
  created_at timestamptz not null default now()
);
create index if not exists open_play_venue_status_idx on public.open_play_sessions(venue_id, status);
create index if not exists open_play_booking_idx on public.open_play_sessions(booking_id, status);
create unique index if not exists open_play_one_active_session_per_booking_idx
  on public.open_play_sessions(booking_id) where status in ('open','full');

create table if not exists public.open_play_participants (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.open_play_sessions(id) on delete cascade,
  player_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'joined' check (status in ('joined','cancelled')),
  attendance_status text not null default 'registered'
    check (attendance_status in ('registered','checked_in','no_show','cancelled')),
  checked_in_at timestamptz,
  joined_at timestamptz not null default now(),
  unique (session_id, player_id)
);
create index if not exists open_play_participants_session_idx
  on public.open_play_participants(session_id, status);
create index if not exists open_play_participants_player_idx
  on public.open_play_participants(player_id, joined_at desc);

create table if not exists public.open_play_checkin_tokens (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.open_play_sessions(id) on delete cascade,
  player_id uuid not null references auth.users(id) on delete cascade,
  token_hash text not null unique,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists open_play_checkin_tokens_expiry_idx
  on public.open_play_checkin_tokens(expires_at) where used_at is null;

create table if not exists public.open_play_checkins (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.open_play_sessions(id) on delete cascade,
  venue_id uuid not null references public.venues(id),
  player_id uuid not null references auth.users(id) on delete cascade,
  checked_in_at timestamptz not null default now(),
  checked_in_by uuid not null references auth.users(id),
  method text not null default 'booth_qr' check (method in ('booth_qr','staff_override')),
  unique (session_id, player_id)
);
create index if not exists open_play_checkins_venue_time_idx
  on public.open_play_checkins(venue_id, checked_in_at desc);

-- RLS: venue data is visible only to active members of that venue (or the player's own rows).
-- SECURITY DEFINER helpers avoid recursive RLS when policies cross-reference membership/session tables.
create or replace function public.is_active_venue_member(p_venue_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.venue_members vm
    where vm.venue_id = p_venue_id and vm.user_id = (select auth.uid()) and vm.is_active
  );
$$;

create or replace function public.can_manage_venue_members(p_venue_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.venue_members vm
    where vm.venue_id = p_venue_id and vm.user_id = (select auth.uid())
      and vm.is_active and vm.role in ('owner','manager')
  );
$$;

create or replace function public.is_open_play_participant(p_session_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.open_play_participants p
    where p.session_id = p_session_id and p.player_id = (select auth.uid())
  );
$$;

create or replace function public.is_open_play_host(p_session_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.open_play_sessions s
    where s.id = p_session_id and s.host_id = (select auth.uid())
  );
$$;


alter table public.venues enable row level security;
alter table public.venue_members enable row level security;
alter table public.open_play_sessions enable row level security;
alter table public.open_play_participants enable row level security;
alter table public.open_play_checkin_tokens enable row level security;
alter table public.open_play_checkins enable row level security;

drop policy if exists "Venue members read their venues" on public.venues;
create policy "Venue members read their venues" on public.venues
for select to authenticated
using (public.is_active_venue_member(venues.id));

drop policy if exists "Users read their own venue memberships" on public.venue_members;
create policy "Users read their own venue memberships" on public.venue_members
for select to authenticated
using (user_id = (select auth.uid()) or public.can_manage_venue_members(venue_members.venue_id));

drop policy if exists "Players and venue staff read open play sessions" on public.open_play_sessions;
create policy "Players and venue staff read open play sessions" on public.open_play_sessions
for select to authenticated
using (
  status in ('open','full')
  or host_id = (select auth.uid())
  or public.is_open_play_participant(open_play_sessions.id)
  or public.is_active_venue_member(open_play_sessions.venue_id)
);

drop policy if exists "Players read participants in relevant sessions" on public.open_play_participants;
create policy "Players read participants in relevant sessions" on public.open_play_participants
for select to authenticated
using (
  player_id = (select auth.uid())
  or public.is_open_play_host(open_play_participants.session_id)
  or exists (
    select 1 from public.open_play_sessions s
    where s.id = open_play_participants.session_id
      and public.is_active_venue_member(s.venue_id)
  )
);

drop policy if exists "Players read their own check-in tokens" on public.open_play_checkin_tokens;
create policy "Players read their own check-in tokens" on public.open_play_checkin_tokens
for select to authenticated using (player_id = (select auth.uid()));

drop policy if exists "Players and venue staff read check-ins" on public.open_play_checkins;
create policy "Players and venue staff read check-ins" on public.open_play_checkins
for select to authenticated
using (
  player_id = (select auth.uid()) or public.is_active_venue_member(open_play_checkins.venue_id)
);

grant select on public.venues, public.venue_members, public.open_play_sessions,
  public.open_play_participants, public.open_play_checkin_tokens, public.open_play_checkins
to authenticated;
revoke insert, update, delete on public.venues, public.venue_members,
  public.open_play_sessions, public.open_play_participants,
  public.open_play_checkin_tokens, public.open_play_checkins from anon, authenticated;

-- Venue owners can create a venue and become its owner; no service key is exposed to the browser.
create or replace function public.create_venue(p_name text, p_location text default null)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_venue_id uuid;
  v_name text := nullif(trim(coalesce(p_name,'')), '');
  v_slug text;
begin
  if v_user is null then raise exception 'Silakan login terlebih dahulu'; end if;
  if v_name is null or length(v_name) > 120 then raise exception 'Nama venue wajib diisi (maksimal 120 karakter)'; end if;
  v_slug := regexp_replace(lower(v_name), '[^a-z0-9]+', '-', 'g');
  v_slug := trim(both '-' from v_slug) || '-' || substr(replace(gen_random_uuid()::text,'-',''),1,8);
  insert into public.venues(name, slug, location, owner_id)
  values (v_name, v_slug, nullif(trim(coalesce(p_location,'')), ''), v_user)
  returning id into v_venue_id;
  insert into public.venue_members(venue_id, user_id, role)
  values (v_venue_id, v_user, 'owner');
  return v_venue_id;
end;
$$;

create or replace function public.create_open_play_session(
  p_booking_id uuid,
  p_title text,
  p_max_players integer,
  p_skill_level text default 'any',
  p_notes text default null
)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_booking public.bookings%rowtype;
  v_session_id uuid;
  v_title text := nullif(trim(coalesce(p_title,'')), '');
begin
  if v_user is null then raise exception 'Silakan login terlebih dahulu'; end if;
  if v_title is null or length(v_title) > 120 then raise exception 'Judul mabar wajib diisi (maksimal 120 karakter)'; end if;
  if p_max_players is null or p_max_players < 2 or p_max_players > 30 then raise exception 'Kuota pemain harus 2–30'; end if;
  if coalesce(p_skill_level,'any') not in ('beginner','intermediate','advanced','any') then raise exception 'Level permainan tidak valid'; end if;

  select * into v_booking from public.bookings where id = p_booking_id for update;
  if not found then raise exception 'Booking tidak ditemukan'; end if;
  if v_booking.created_by is distinct from v_user then raise exception 'Mabar hanya bisa dibuat dari booking milik akun ini'; end if;
  if v_booking.status <> 'confirmed' then raise exception 'Booking harus berstatus confirmed sebelum dibuka sebagai mabar'; end if;
  if ((v_booking.booking_date + v_booking.start_time) at time zone 'Asia/Jakarta') <= now() then raise exception 'Waktu booking sudah lewat'; end if;
  if exists (select 1 from public.open_play_sessions s where s.booking_id = p_booking_id and s.status in ('open','full')) then
    raise exception 'Booking ini sudah memiliki sesi mabar aktif'; end if;

  insert into public.open_play_sessions(venue_id, booking_id, host_id, title, max_players, skill_level, notes)
  values (v_booking.venue_id, v_booking.id, v_user, v_title, p_max_players, coalesce(p_skill_level,'any'), nullif(trim(coalesce(p_notes,'')), ''))
  returning id into v_session_id;

  insert into public.open_play_participants(session_id, player_id, status, attendance_status)
  values (v_session_id, v_user, 'joined', 'registered');

  if p_max_players = 1 then
    update public.open_play_sessions set status = 'full' where id = v_session_id;
  end if;
  return v_session_id;
end;
$$;

create or replace function public.join_open_play_session(p_session_id uuid)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_session public.open_play_sessions%rowtype;
  v_existing text;
  v_joined integer;
begin
  if v_user is null then raise exception 'Silakan login terlebih dahulu'; end if;
  select * into v_session from public.open_play_sessions where id = p_session_id for update;
  if not found then raise exception 'Sesi mabar tidak ditemukan'; end if;
  if v_session.status <> 'open' then raise exception 'Sesi ini tidak lagi menerima pemain'; end if;
  if ((select booking_date + start_time from public.bookings where id = v_session.booking_id) at time zone 'Asia/Jakarta') <= now() then
    raise exception 'Sesi sudah dimulai'; end if;
  select status into v_existing from public.open_play_participants where session_id = p_session_id and player_id = v_user;
  if v_existing = 'joined' then return 'already_joined'; end if;
  select count(*) into v_joined from public.open_play_participants where session_id = p_session_id and status = 'joined';
  if v_joined >= v_session.max_players then
    update public.open_play_sessions set status = 'full' where id = p_session_id;
    raise exception 'Kuota mabar sudah penuh';
  end if;
  insert into public.open_play_participants(session_id, player_id, status, attendance_status)
  values (p_session_id, v_user, 'joined', 'registered')
  on conflict (session_id, player_id) do update set status = 'joined', attendance_status = 'registered', checked_in_at = null, joined_at = now();
  select count(*) into v_joined from public.open_play_participants where session_id = p_session_id and status = 'joined';
  if v_joined >= v_session.max_players then update public.open_play_sessions set status = 'full' where id = p_session_id; end if;
  return 'joined';
end;
$$;

create or replace function public.leave_open_play_session(p_session_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_session public.open_play_sessions%rowtype;
begin
  if v_user is null then raise exception 'Silakan login terlebih dahulu'; end if;
  select * into v_session from public.open_play_sessions where id = p_session_id for update;
  if not found then raise exception 'Sesi mabar tidak ditemukan'; end if;
  if v_session.host_id = v_user then raise exception 'Host tidak bisa keluar; batalkan sesi atau serahkan host terlebih dahulu'; end if;
  if v_session.status not in ('open','full') then raise exception 'Sesi ini sudah ditutup'; end if;
  update public.open_play_participants
  set status = 'cancelled', attendance_status = 'cancelled', checked_in_at = null
  where session_id = p_session_id and player_id = v_user and status = 'joined';
  if not found then raise exception 'Kamu belum bergabung ke sesi ini'; end if;
  update public.open_play_sessions set status = 'open' where id = p_session_id and status = 'full';
end;
$$;

-- Return a short-lived one-time token; the raw token is never stored in the database.
create or replace function public.create_open_play_checkin_token(p_session_id uuid)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_session public.open_play_sessions%rowtype;
  v_booking public.bookings%rowtype;
  v_token text := gen_random_uuid()::text || gen_random_uuid()::text;
begin
  if v_user is null then raise exception 'Silakan login terlebih dahulu'; end if;
  select * into v_session from public.open_play_sessions where id = p_session_id;
  if not found then raise exception 'Sesi mabar tidak ditemukan'; end if;
  select * into v_booking from public.bookings where id = v_session.booking_id;
  if not exists (
    select 1 from public.open_play_participants p
    where p.session_id = p_session_id and p.player_id = v_user
      and p.status = 'joined' and p.attendance_status = 'registered'
  ) then raise exception 'Hanya peserta yang belum check-in yang dapat membuat QR'; end if;
  if now() < ((v_booking.booking_date + v_booking.start_time) at time zone 'Asia/Jakarta') - interval '3 hours'
     or now() > ((v_booking.booking_date + v_booking.start_time) at time zone 'Asia/Jakarta')
       + make_interval(hours => v_booking.duration_hours) + interval '2 hours' then
    raise exception 'QR check-in hanya tersedia mendekati jadwal bermain'; end if;
  insert into public.open_play_checkin_tokens(session_id, player_id, token_hash, expires_at)
  values (p_session_id, v_user, encode(public.digest(v_token, 'sha256'), 'hex'), now() + interval '2 minutes');
  return v_token;
end;
$$;

-- Booth operator must be an active member of the venue where the session is booked.
create or replace function public.redeem_open_play_checkin_token(p_token text)
returns table(player_id uuid, player_name text, session_id uuid, session_title text, checked_in_at timestamptz)
language plpgsql security definer set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_token public.open_play_checkin_tokens%rowtype;
  v_session public.open_play_sessions%rowtype;
  v_booking public.bookings%rowtype;
  v_player_name text;
  v_now timestamptz := now();
begin
  if v_user is null then raise exception 'Silakan login sebagai petugas venue'; end if;
  if p_token is null or length(p_token) < 32 or length(p_token) > 100 then raise exception 'QR tidak valid'; end if;

  select t.* into v_token
  from public.open_play_checkin_tokens t
  where t.token_hash = encode(public.digest(p_token, 'sha256'), 'hex')
  for update;
  if not found then raise exception 'QR tidak valid atau sudah kedaluwarsa'; end if;
  if v_token.used_at is not null then raise exception 'QR ini sudah pernah digunakan'; end if;
  if v_token.expires_at <= v_now then raise exception 'QR sudah kedaluwarsa. Minta pemain membuat QR baru'; end if;

  select * into v_session from public.open_play_sessions where id = v_token.session_id;
  select * into v_booking from public.bookings where id = v_session.booking_id;
  if not exists (
    select 1 from public.venue_members vm
    where vm.venue_id = v_session.venue_id and vm.user_id = v_user and vm.is_active
  ) then raise exception 'Akun petugas tidak memiliki akses ke venue sesi ini'; end if;
  if v_session.status not in ('open','full') then raise exception 'Sesi ini sudah ditutup'; end if;
  if v_now < ((v_booking.booking_date + v_booking.start_time) at time zone 'Asia/Jakarta') - interval '3 hours'
     or v_now > ((v_booking.booking_date + v_booking.start_time) at time zone 'Asia/Jakarta')
       + make_interval(hours => v_booking.duration_hours) + interval '2 hours' then
    raise exception 'Di luar jendela waktu check-in'; end if;
  if not exists (
    select 1 from public.open_play_participants p
    where p.session_id = v_token.session_id and p.player_id = v_token.player_id and p.status = 'joined'
      and p.attendance_status = 'registered'
  ) then raise exception 'Peserta tidak terdaftar atau sudah check-in'; end if;

  select coalesce(nullif(trim(p.display_name),''), split_part(coalesce(u.email,'pemain'),'@',1))
  into v_player_name from auth.users u left join public.profiles p on p.id = u.id
  where u.id = v_token.player_id;

  insert into public.open_play_checkins(session_id, venue_id, player_id, checked_in_by, method)
  values (v_token.session_id, v_session.venue_id, v_token.player_id, v_user, 'booth_qr');
  update public.open_play_participants
  set attendance_status = 'checked_in', checked_in_at = v_now
  where session_id = v_token.session_id and player_id = v_token.player_id;
  update public.open_play_checkin_tokens set used_at = v_now where id = v_token.id;

  return query select v_token.player_id, v_player_name, v_session.id, v_session.title, v_now;
end;
$$;

revoke all on function public.is_active_venue_member(uuid) from public;
revoke all on function public.can_manage_venue_members(uuid) from public;
revoke all on function public.is_open_play_participant(uuid) from public;
revoke all on function public.is_open_play_host(uuid) from public;
grant execute on function public.is_active_venue_member(uuid) to authenticated;
grant execute on function public.can_manage_venue_members(uuid) to authenticated;
grant execute on function public.is_open_play_participant(uuid) to authenticated;
grant execute on function public.is_open_play_host(uuid) to authenticated;

revoke all on function public.create_venue(text,text) from public;
revoke all on function public.create_open_play_session(uuid,text,integer,text,text) from public;
revoke all on function public.join_open_play_session(uuid) from public;
revoke all on function public.leave_open_play_session(uuid) from public;
revoke all on function public.create_open_play_checkin_token(uuid) from public;
revoke all on function public.redeem_open_play_checkin_token(text) from public;
grant execute on function public.create_venue(text,text) to authenticated;
grant execute on function public.create_open_play_session(uuid,text,integer,text,text) to authenticated;
grant execute on function public.join_open_play_session(uuid) to authenticated;
grant execute on function public.leave_open_play_session(uuid) to authenticated;
grant execute on function public.create_open_play_checkin_token(uuid) to authenticated;
grant execute on function public.redeem_open_play_checkin_token(text) to authenticated;

commit;
