-- Fix ambiguous output-column references in QR redemption.
-- redeem_open_play_checkin_token returns player_id and session_id, so qualify
-- all participant columns in UPDATE statements.
begin;

create or replace function public.redeem_open_play_checkin_token(p_token text)
returns table(player_id uuid, player_name text, session_id uuid, session_title text, checked_in_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user uuid := (select auth.uid());
  v_token_id uuid;
  v_token_session_id uuid;
  v_token_player_id uuid;
  v_token_expires_at timestamptz;
  v_token_used_at timestamptz;
  v_session_venue_id uuid;
  v_session_status text;
  v_session_title text;
  v_booking_id uuid;
  v_booking_date date;
  v_start_time time;
  v_duration_hours integer;
  v_player_name text;
  v_now timestamptz := now();
begin
  if v_user is null then
    raise exception 'Silakan login sebagai petugas venue';
  end if;

  if p_token is null or length(p_token) < 32 or length(p_token) > 100 then
    raise exception 'QR tidak valid';
  end if;

  select t.id, t.session_id, t.player_id, t.expires_at, t.used_at
    into v_token_id, v_token_session_id, v_token_player_id, v_token_expires_at, v_token_used_at
  from public.open_play_checkin_tokens as t
  where t.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
  for update;

  if not found then
    raise exception 'QR tidak valid atau sudah kedaluwarsa';
  end if;
  if v_token_used_at is not null then
    raise exception 'QR ini sudah pernah digunakan';
  end if;
  if v_token_expires_at <= v_now then
    raise exception 'QR sudah kedaluwarsa. Minta pemain membuat QR baru';
  end if;

  select s.venue_id, s.status, s.title, s.booking_id
    into v_session_venue_id, v_session_status, v_session_title, v_booking_id
  from public.open_play_sessions as s
  where s.id = v_token_session_id;

  if not found then
    raise exception 'Sesi mabar tidak ditemukan';
  end if;

  select b.booking_date, b.start_time, b.duration_hours
    into v_booking_date, v_start_time, v_duration_hours
  from public.bookings as b
  where b.id = v_booking_id;

  if not found then
    raise exception 'Booking sesi tidak ditemukan';
  end if;

  if not exists (
    select 1
    from public.venue_members as vm
    where vm.venue_id = v_session_venue_id
      and vm.user_id = v_user
      and vm.is_active
  ) then
    raise exception 'Akun petugas tidak memiliki akses ke venue sesi ini';
  end if;

  if v_session_status not in ('open', 'full') then
    raise exception 'Sesi ini sudah ditutup';
  end if;

  if v_now < ((v_booking_date + v_start_time) at time zone 'Asia/Jakarta') - interval '3 hours'
     or v_now > ((v_booking_date + v_start_time) at time zone 'Asia/Jakarta')
       + make_interval(hours => v_duration_hours) + interval '2 hours' then
    raise exception 'Di luar jendela waktu check-in';
  end if;

  if not exists (
    select 1
    from public.open_play_participants as p
    where p.session_id = v_token_session_id
      and p.player_id = v_token_player_id
      and p.status = 'joined'
      and p.attendance_status = 'registered'
  ) then
    raise exception 'Peserta tidak terdaftar atau sudah check-in';
  end if;

  select coalesce(
           nullif(trim(p.display_name), ''),
           split_part(coalesce(u.email, 'pemain'), '@', 1)
         )
    into v_player_name
  from auth.users as u
  left join public.profiles as p on p.id = u.id
  where u.id = v_token_player_id;

  insert into public.open_play_checkins(session_id, venue_id, player_id, checked_in_by, method)
  values (v_token_session_id, v_session_venue_id, v_token_player_id, v_user, 'booth_qr');

  update public.open_play_participants as op
  set attendance_status = 'checked_in',
      checked_in_at = v_now
  where op.session_id = v_token_session_id
    and op.player_id = v_token_player_id;

  update public.open_play_checkin_tokens as tok
  set used_at = v_now
  where tok.id = v_token_id;

  return query
  select v_token_player_id, v_player_name, v_token_session_id, v_session_title, v_now;
end;
$function$;

commit;
