-- Expire unconfirmed booking holds after 10 minutes from creation.
-- A pending booking is a temporary hold, not a no-show caused by late arrival.
-- Once expired, status becomes cancelled so overlap checks release the slot.
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
  set status = 'cancelled'
  where b.status = 'pending'
    and b.created_at <= now() - interval '10 minutes';

  get diagnostics v_expired_count = row_count;
  return v_expired_count;
end;
$function$;

revoke all on function public.expire_unconfirmed_bookings() from public, anon, authenticated;
grant execute on function public.expire_unconfirmed_bookings() to postgres, service_role;

-- Keep the existing booking-status sweep intact; this is a separate job so
-- the 10-minute confirmation timeout is measured from created_at, not kickoff.
select cron.schedule(
  'futsalkita-expire-unconfirmed-bookings',
  '* * * * *',
  'select public.expire_unconfirmed_bookings();'
);

commit;
