-- Allow the lifecycle status introduced by migration 012.
-- Existing deployments may have a check constraint that predates 'playing'.
begin;

alter table public.bookings
  drop constraint if exists bookings_status_check;

alter table public.bookings
  add constraint bookings_status_check
  check (status in ('pending', 'confirmed', 'playing', 'cancelled', 'completed', 'no_show'));

commit;
