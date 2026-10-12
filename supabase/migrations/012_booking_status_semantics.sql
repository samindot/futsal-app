-- Align booking status transitions with the confirmed business rules.
-- Pending confirmation expires 10 minutes after creation (handled by the
-- existing futsalkita-expire-unconfirmed-bookings cron).
-- Confirmed bookings become playing at scheduled start, then completed
-- 2 hours after scheduled end. Check-in delay does not cancel a confirmed booking.

begin;

create or replace function public.expire_unconfirmed_bookings()
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_expired_count integer := 0;
begin
  update public.bookings as b
  set status = 'no_show'
  where b.status = 'pending'
    and b.created_at <= now() - interval '10 minutes';

  get diagnostics v_expired_count = row_count;
  return v_expired_count;
end;
$function$;

create or replace function public.refresh_booking_statuses()
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_updated integer := 0;
  v_count integer := 0;
begin
  -- A confirmed booking starts playing at the scheduled start time.
  -- Do not mark it no-show for missing a QR check-in.
  update public.bookings as b
  set status = 'playing'
  where b.status = 'confirmed'
    and ((b.booking_date + b.start_time) at time zone 'Asia/Jakarta') <= now();

  get diagnostics v_count = row_count;
  v_updated := v_updated + v_count;

  -- Keep the existing completion grace period: 2 hours after scheduled end.
  update public.bookings as b
  set status = 'completed'
  where b.status = 'playing'
    and (((b.booking_date + b.start_time) at time zone 'Asia/Jakarta')
      + make_interval(hours => b.duration_hours) + interval '2 hours') <= now();

  get diagnostics v_count = row_count;
  v_updated := v_updated + v_count;

  return v_updated;
end;
$function$;

commit;
