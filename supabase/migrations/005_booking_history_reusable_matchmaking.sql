-- Booking history and reusable matchmaking sessions linked to a booking.
begin;

alter table public.matchmaking_sessions
  add column if not exists booking_id uuid references public.bookings(id) on delete set null;
create index if not exists matchmaking_sessions_booking_idx
  on public.matchmaking_sessions(booking_id, status);

-- Link older sessions to their original booking when the match is unambiguous.
update public.matchmaking_sessions s
set booking_id = (
  select b.id
  from public.bookings b
  join public.fields f on f.id = b.field_id
  where b.created_by = s.host_id
    and b.booking_date = s.session_date
    and b.start_time = s.start_time
    and b.duration_hours = s.duration_hours
    and (
      s.venue = f.name
      or s.venue = f.name || ' — ' || trim(coalesce(f.location, ''))
      or s.venue = f.name || ' · ' || trim(coalesce(f.location, ''))
    )
  limit 1
)
where s.booking_id is null
  and (
    select count(*)
    from public.bookings b
    join public.fields f on f.id = b.field_id
    where b.created_by = s.host_id
      and b.booking_date = s.session_date
      and b.start_time = s.start_time
      and b.duration_hours = s.duration_hours
      and (
        s.venue = f.name
        or s.venue = f.name || ' — ' || trim(coalesce(f.location, ''))
      )
  ) = 1;

create or replace function public.create_matchmaking_for_booking(
  p_booking_id uuid,
  p_title text,
  p_skill_level text default 'any',
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_booking public.bookings%rowtype;
  v_field public.fields%rowtype;
  v_session_id uuid;
  v_title text := nullif(trim(coalesce(p_title, '')), '');
  v_venue text;
begin
  if (select auth.uid()) is null then
    raise exception 'Silakan login terlebih dahulu';
  end if;
  if v_title is null or length(v_title) > 100 then
    raise exception 'Nama tim / judul sparing wajib diisi (maksimal 100 karakter)';
  end if;
  if coalesce(p_skill_level, 'any') not in ('beginner','intermediate','advanced','any') then
    raise exception 'Level sparing tidak valid';
  end if;

  select * into v_booking
  from public.bookings
  where id = p_booking_id
  for update;
  if not found then raise exception 'Booking tidak ditemukan'; end if;
  if v_booking.created_by is distinct from (select auth.uid()) then
    raise exception 'Kamu hanya bisa membuat pencarian dari booking milikmu';
  end if;
  if v_booking.status not in ('pending','confirmed') then
    raise exception 'Hanya booking yang masih aktif yang bisa digunakan untuk mencari lawan';
  end if;
  if v_booking.booking_date < (now() at time zone 'Asia/Jakarta')::date then
    raise exception 'Tanggal booking sudah lewat';
  end if;
  if exists (
    select 1 from public.matchmaking_sessions s
    where s.booking_id = p_booking_id and s.status in ('open','full')
  ) then
    raise exception 'Booking ini sudah memiliki pencarian lawan yang aktif';
  end if;

  select * into v_field from public.fields where id = v_booking.field_id;
  if not found then raise exception 'Data lapangan tidak ditemukan'; end if;
  v_venue := v_field.name || case when nullif(trim(coalesce(v_field.location,'')), '') is null then '' else ' — ' || trim(v_field.location) end;

  insert into public.matchmaking_sessions (
    host_id, booking_id, title, venue, session_date, start_time,
    duration_hours, skill_level, max_players, notes, status
  ) values (
    (select auth.uid()), p_booking_id, v_title, v_venue, v_booking.booking_date,
    v_booking.start_time, v_booking.duration_hours, coalesce(p_skill_level, 'any'),
    2, nullif(trim(coalesce(p_notes, '')), ''), 'open'
  ) returning id into v_session_id;

  return v_session_id;
end;
$$;

create or replace function public.cancel_matchmaking_session(p_session_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.matchmaking_sessions%rowtype;
  v_opponent uuid;
begin
  if (select auth.uid()) is null then raise exception 'Silakan login terlebih dahulu'; end if;

  select * into v_session
  from public.matchmaking_sessions
  where id = p_session_id
  for update;
  if not found then raise exception 'Jadwal sparing tidak ditemukan'; end if;
  if v_session.host_id <> (select auth.uid()) then
    raise exception 'Hanya pembuat jadwal yang bisa membatalkan pencarian';
  end if;
  if v_session.status not in ('open','full') then
    raise exception 'Pencarian ini sudah tidak aktif';
  end if;

  select player_id into v_opponent
  from public.matchmaking_players
  where session_id = p_session_id
    and player_id <> v_session.host_id
    and status = 'joined'
  limit 1;

  if v_opponent is not null then
    insert into public.matchmaking_notifications(recipient_id, session_id, message)
    values (
      v_opponent, p_session_id,
      'Pencarian sparing "' || v_session.title || '" pada ' ||
      to_char(v_session.session_date, 'DD Mon YYYY') || ' pukul ' ||
      to_char(v_session.start_time, 'HH24:MI') || ' dibatalkan oleh pembuat jadwal.'
    );
  end if;

  update public.matchmaking_sessions
  set status = 'cancelled'
  where id = p_session_id;
end;
$$;

grant execute on function public.create_matchmaking_for_booking(uuid,text,text,text) to authenticated;
grant execute on function public.cancel_matchmaking_session(uuid) to authenticated;

commit;
