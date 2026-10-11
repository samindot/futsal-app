-- Automated booking lifecycle:
-- pending -> no_show 10 minutes after scheduled start
-- confirmed -> completed 2 hours after scheduled end
begin;

alter table public.bookings drop constraint if exists bookings_status_check;
alter table public.bookings add constraint bookings_status_check
  check (status in ('pending','confirmed','cancelled','completed','no_show'));

create or replace function public.refresh_booking_statuses()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_updated integer := 0;
  v_count integer := 0;
begin
  update public.bookings b
  set status = 'no_show'
  where b.status = 'pending'
    and ((b.booking_date + b.start_time) at time zone 'Asia/Jakarta') <= now() - interval '10 minutes';
  get diagnostics v_count = row_count;
  v_updated := v_updated + v_count;

  update public.bookings b
  set status = 'completed'
  where b.status = 'confirmed'
    and (((b.booking_date + b.start_time) at time zone 'Asia/Jakarta')
      + make_interval(hours => b.duration_hours) + interval '2 hours') <= now();
  get diagnostics v_count = row_count;
  v_updated := v_updated + v_count;

  return v_updated;
end;
$$;

revoke all on function public.refresh_booking_statuses() from public;
grant execute on function public.refresh_booking_statuses() to authenticated, service_role;

-- Supabase projects commonly provide pg_cron. If it is not enabled, the app
-- also calls this idempotent function when the dashboard/calendar is opened.
do $schedule$
begin
  begin
    execute 'create extension if not exists pg_cron';
  exception when others then
    raise notice 'pg_cron could not be enabled; app-triggered status refresh remains available: %', sqlerrm;
  end;
  begin
    perform cron.unschedule('futsalkita-booking-status-sweep');
  exception when others then
    null;
  end;
  begin
    perform cron.schedule(
      'futsalkita-booking-status-sweep',
      '* * * * *',
      'select public.refresh_booking_statuses();'
    );
  exception when others then
    raise notice 'pg_cron schedule unavailable; app-triggered status refresh remains available: %', sqlerrm;
  end;
end;
$schedule$;

commit;
