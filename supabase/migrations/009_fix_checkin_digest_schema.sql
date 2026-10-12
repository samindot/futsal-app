-- Fix pgcrypto function schema qualification for Supabase projects where pgcrypto lives in extensions.
begin;

create schema if not exists extensions;
do $migration$
declare
  ext_schema text;
begin
  select n.nspname into ext_schema
  from pg_catalog.pg_extension e
  join pg_catalog.pg_namespace n on n.oid = e.extnamespace
  where e.extname = 'pgcrypto';

  if ext_schema is null then
    create extension pgcrypto with schema extensions;
  elsif ext_schema <> 'extensions' then
    execute 'alter extension pgcrypto set schema extensions';
  end if;
end;
$migration$;

create or replace function public.create_open_play_checkin_token(p_session_id uuid)
returns text
language plpgsql security definer set search_path = ''
as '
declare
  v_user uuid := (select auth.uid());
  v_session public.open_play_sessions%rowtype;
  v_booking public.bookings%rowtype;
  v_token text := gen_random_uuid()::text || gen_random_uuid()::text;
begin
  if v_user is null then raise exception ''Silakan login terlebih dahulu''; end if;
  select * into v_session from public.open_play_sessions where id = p_session_id;
  if not found then raise exception ''Sesi mabar tidak ditemukan''; end if;
  select * into v_booking from public.bookings where id = v_session.booking_id;
  if not exists (
    select 1 from public.open_play_participants p
    where p.session_id = p_session_id and p.player_id = v_user
      and p.status = ''joined'' and p.attendance_status = ''registered''
  ) then raise exception ''Hanya peserta yang belum check-in yang dapat membuat QR''; end if;
  if now() < ((v_booking.booking_date + v_booking.start_time) at time zone ''Asia/Jakarta'') - interval ''3 hours''
     or now() > ((v_booking.booking_date + v_booking.start_time) at time zone ''Asia/Jakarta'')
       + make_interval(hours => v_booking.duration_hours) + interval ''2 hours'' then
    raise exception ''QR check-in hanya tersedia mendekati jadwal bermain''; end if;
  insert into public.open_play_checkin_tokens(session_id, player_id, token_hash, expires_at)
  values (p_session_id, v_user, encode(extensions.digest(v_token, ''sha256''), ''hex''), now() + interval ''2 minutes'');
  return v_token;
end;
';

-- Booth operator must be an active member of the venue where the session is booked.
create or replace function public.redeem_open_play_checkin_token(p_token text)
returns table(player_id uuid, player_name text, session_id uuid, session_title text, checked_in_at timestamptz)
language plpgsql security definer set search_path = ''
as '
declare
  v_user uuid := (select auth.uid());
  v_token public.open_play_checkin_tokens%rowtype;
  v_session public.open_play_sessions%rowtype;
  v_booking public.bookings%rowtype;
  v_player_name text;
  v_now timestamptz := now();
begin
  if v_user is null then raise exception ''Silakan login sebagai petugas venue''; end if;
  if p_token is null or length(p_token) < 32 or length(p_token) > 100 then raise exception ''QR tidak valid''; end if;

  select t.* into v_token
  from public.open_play_checkin_tokens t
  where t.token_hash = encode(extensions.digest(p_token, ''sha256''), ''hex'')
  for update;
  if not found then raise exception ''QR tidak valid atau sudah kedaluwarsa''; end if;
  if v_token.used_at is not null then raise exception ''QR ini sudah pernah digunakan''; end if;
  if v_token.expires_at <= v_now then raise exception ''QR sudah kedaluwarsa. Minta pemain membuat QR baru''; end if;

  select * into v_session from public.open_play_sessions where id = v_token.session_id;
  select * into v_booking from public.bookings where id = v_session.booking_id;
  if not exists (
    select 1 from public.venue_members vm
    where vm.venue_id = v_session.venue_id and vm.user_id = v_user and vm.is_active
  ) then raise exception ''Akun petugas tidak memiliki akses ke venue sesi ini''; end if;
  if v_session.status not in (''open'',''full'') then raise exception ''Sesi ini sudah ditutup''; end if;
  if v_now < ((v_booking.booking_date + v_booking.start_time) at time zone ''Asia/Jakarta'') - interval ''3 hours''
     or v_now > ((v_booking.booking_date + v_booking.start_time) at time zone ''Asia/Jakarta'')
       + make_interval(hours => v_booking.duration_hours) + interval ''2 hours'' then
    raise exception ''Di luar jendela waktu check-in''; end if;
  if not exists (
    select 1 from public.open_play_participants p
    where p.session_id = v_token.session_id and p.player_id = v_token.player_id and p.status = ''joined''
      and p.attendance_status = ''registered''
  ) then raise exception ''Peserta tidak terdaftar atau sudah check-in''; end if;

  select coalesce(nullif(trim(p.display_name),''''), split_part(coalesce(u.email,''pemain''),''@'',1))
  into v_player_name from auth.users u left join public.profiles p on p.id = u.id
  where u.id = v_token.player_id;

  insert into public.open_play_checkins(session_id, venue_id, player_id, checked_in_by, method)
  values (v_token.session_id, v_session.venue_id, v_token.player_id, v_user, ''booth_qr'');
  update public.open_play_participants
  set attendance_status = ''checked_in'', checked_in_at = v_now
  where session_id = v_token.session_id and player_id = v_token.player_id;
  update public.open_play_checkin_tokens set used_at = v_now where id = v_token.id;

  return query select v_token.player_id, v_player_name, v_session.id, v_session.title, v_now;
end;
';


commit;
