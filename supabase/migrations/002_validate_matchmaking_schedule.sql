-- Enforce valid future matchmaking schedules at the database boundary.
-- This migration is additive; it does not rewrite prior migrations or existing data.
begin;

create or replace function public.validate_matchmaking_schedule()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_today date := (now() at time zone 'Asia/Jakarta')::date;
  v_now time := (now() at time zone 'Asia/Jakarta')::time;
begin
  -- Allow hosts/admins to cancel or complete an old session without being
  -- blocked by schedule validation. Validate only inserts and schedule edits.
  if tg_op = 'UPDATE'
     and new.session_date is not distinct from old.session_date
     and new.start_time is not distinct from old.start_time
     and new.duration_hours is not distinct from old.duration_hours then
    return new;
  end if;

  if new.session_date is null or new.session_date < v_today then
    raise exception 'Tanggal sesi tidak boleh di masa lalu';
  end if;

  if new.start_time is null
     or new.start_time < time '08:00'
     or new.start_time >= time '24:00' then
    raise exception 'Jam mulai harus antara 08:00 dan 23:00';
  end if;

  if new.session_date = v_today and new.start_time <= v_now then
    raise exception 'Jam mulai sesi harus di masa depan';
  end if;

  if new.duration_hours is null
     or new.duration_hours < 1
     or new.duration_hours > 8
     or extract(epoch from new.start_time) + new.duration_hours * 3600 > 86400 then
    raise exception 'Durasi atau jam selesai sesi tidak valid';
  end if;

  return new;
end;
$$;

drop trigger if exists validate_matchmaking_schedule_before_write
  on public.matchmaking_sessions;
create trigger validate_matchmaking_schedule_before_write
before insert or update on public.matchmaking_sessions
for each row execute function public.validate_matchmaking_schedule();

commit;
