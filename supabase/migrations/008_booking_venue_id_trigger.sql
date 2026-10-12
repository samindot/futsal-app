-- Ensure booking RPCs created before the multi-venue migration remain compatible.
-- Derive venue_id from the selected field on every booking insert; never trust a client-supplied venue_id.
begin;

create or replace function public.set_booking_venue_from_field()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_venue_id uuid;
begin
  select f.venue_id
    into v_venue_id
  from public.fields as f
  where f.id = new.field_id;

  if v_venue_id is null then
    raise exception 'Lapangan tidak ditemukan atau belum terhubung ke venue aktif';
  end if;

  if new.venue_id is not null and new.venue_id is distinct from v_venue_id then
    raise exception 'Venue booking tidak sesuai dengan venue lapangan';
  end if;

  new.venue_id := v_venue_id;
  return new;
end;
$function$;

drop trigger if exists bookings_set_venue_from_field on public.bookings;

create trigger bookings_set_venue_from_field
before insert or update of field_id, venue_id on public.bookings
for each row
execute function public.set_booking_venue_from_field();

commit;
