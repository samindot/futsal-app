-- Add customer WhatsApp details to bookings and support per-field rate management.
-- Apply this migration manually in Supabase SQL Editor after reviewing it.
begin;

alter table public.bookings
  add column if not exists whatsapp_number text;

drop function if exists public.create_booking(uuid,date,time,integer,numeric,text,text);
drop function if exists public.request_booking(uuid,date,time,integer,text,text);

create function public.create_booking(
  p_field_id uuid,
  p_date date,
  p_start time,
  p_duration integer,
  p_amount_paid numeric default 0,
  p_notes text default null,
  p_customer_name text default null,
  p_whatsapp_number text default null
)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  v_booking_id uuid;
  v_customer_name text;
  v_whatsapp_number text;
begin
  if (select auth.uid()) is null or not public.is_admin() then
    raise exception 'Only authenticated admins can create bookings';
  end if;
  if p_date is null or p_date < (now() at time zone 'Asia/Jakarta')::date then
    raise exception 'Booking date cannot be in the past';
  end if;
  if p_start is null or p_start < time '08:00' or p_start >= time '24:00' then
    raise exception 'Start time must be between 08:00 and 23:00';
  end if;
  if p_date = (now() at time zone 'Asia/Jakarta')::date
     and p_start <= (now() at time zone 'Asia/Jakarta')::time then
    raise exception 'Booking start time must be in the future';
  end if;
  if p_duration is null or p_duration < 1 or p_duration > 8
     or extract(epoch from p_start) + p_duration * 3600 > 86400 then
    raise exception 'Invalid booking duration or end time';
  end if;
  v_customer_name := nullif(trim(coalesce(p_customer_name, '')), '');
  v_whatsapp_number := nullif(trim(coalesce(p_whatsapp_number, '')), '');
  if v_customer_name is null then raise exception 'Customer name is required'; end if;
  if v_whatsapp_number is null then raise exception 'WhatsApp number is required'; end if;
  if coalesce(p_amount_paid, 0) < 0 then raise exception 'Amount paid cannot be negative'; end if;

  perform pg_advisory_xact_lock(hashtext(p_field_id::text), hashtext(p_date::text));
  perform 1 from public.fields where id = p_field_id and is_active = true;
  if not found then raise exception 'Field not found or inactive'; end if;

  if exists (
    select 1 from public.bookings b
    where b.field_id = p_field_id and b.booking_date = p_date and b.status <> 'cancelled'
      and b.start_time < p_start + make_interval(hours => p_duration)
      and b.start_time + make_interval(hours => b.duration_hours) > p_start
  ) then raise exception 'This time slot overlaps an existing booking'; end if;

  insert into public.bookings (
    field_id, booking_date, start_time, duration_hours, customer_name,
    whatsapp_number, amount_paid, notes, created_by
  ) values (
    p_field_id, p_date, p_start, p_duration, v_customer_name,
    v_whatsapp_number, coalesce(p_amount_paid, 0),
    nullif(trim(coalesce(p_notes, '')), ''), (select auth.uid())
  ) returning id into v_booking_id;
  return v_booking_id;
end;
$$;

create function public.request_booking(
  p_field_id uuid,
  p_date date,
  p_start time,
  p_duration integer,
  p_customer_name text default null,
  p_notes text default null,
  p_whatsapp_number text default null
)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  v_booking_id uuid;
  v_customer_name text;
  v_whatsapp_number text;
begin
  if (select auth.uid()) is null then raise exception 'Silakan login untuk mengajukan booking'; end if;
  if p_date is null or p_date < (now() at time zone 'Asia/Jakarta')::date then raise exception 'Tanggal booking tidak boleh di masa lalu'; end if;
  if p_start is null or p_start < time '08:00' or p_start >= time '24:00' then
    raise exception 'Jam mulai harus antara 08:00 dan 23:00';
  end if;
  if p_date = (now() at time zone 'Asia/Jakarta')::date
     and p_start <= (now() at time zone 'Asia/Jakarta')::time then
    raise exception 'Jam mulai booking harus di masa depan';
  end if;
  if p_duration is null or p_duration < 1 or p_duration > 8
     or extract(epoch from p_start) + p_duration * 3600 > 86400 then
    raise exception 'Durasi atau jam selesai tidak valid';
  end if;
  select nullif(trim(coalesce(p_customer_name, '')), '') into v_customer_name;
  if v_customer_name is null then
    select coalesce(nullif(trim(p.display_name), ''), split_part(coalesce(u.email, 'player'), '@', 1))
      into v_customer_name
    from public.profiles p join auth.users u on u.id = p.id
    where p.id = (select auth.uid());
  end if;
  if v_customer_name is null then raise exception 'Nama pelanggan wajib diisi di profil atau formulir'; end if;
  v_whatsapp_number := nullif(trim(coalesce(p_whatsapp_number, '')), '');
  if v_whatsapp_number is null then raise exception 'Nomor WhatsApp wajib diisi'; end if;

  perform pg_advisory_xact_lock(hashtext(p_field_id::text), hashtext(p_date::text));
  perform 1 from public.fields where id = p_field_id and is_active = true;
  if not found then raise exception 'Lapangan tidak ditemukan atau tidak aktif'; end if;
  if exists (
    select 1 from public.bookings b
    where b.field_id = p_field_id and b.booking_date = p_date and b.status <> 'cancelled'
      and b.start_time < p_start + make_interval(hours => p_duration)
      and b.start_time + make_interval(hours => b.duration_hours) > p_start
  ) then raise exception 'Slot ini baru saja terisi. Silakan pilih jam lain'; end if;

  insert into public.bookings (
    field_id, booking_date, start_time, duration_hours, customer_name,
    whatsapp_number, amount_paid, notes, status, created_by
  ) values (
    p_field_id, p_date, p_start, p_duration, v_customer_name,
    v_whatsapp_number, 0, nullif(trim(coalesce(p_notes, '')), ''), 'pending', (select auth.uid())
  ) returning id into v_booking_id;
  return v_booking_id;
end;
$$;

grant execute on function public.create_booking(uuid,date,time,integer,numeric,text,text,text) to authenticated;
grant execute on function public.request_booking(uuid,date,time,integer,text,text,text) to authenticated;

commit;
