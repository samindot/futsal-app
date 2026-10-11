-- Matchmaking is team-vs-team: one opposing team can claim each open session.
-- Also create persistent in-app notifications for session hosts.
begin;

alter table public.matchmaking_players add column if not exists team_name text;

create table if not exists public.matchmaking_notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references auth.users(id) on delete cascade,
  session_id uuid not null references public.matchmaking_sessions(id) on delete cascade,
  message text not null,
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index if not exists matchmaking_notifications_recipient_idx
  on public.matchmaking_notifications(recipient_id, created_at desc);

alter table public.matchmaking_notifications enable row level security;
drop policy if exists "Users read own matchmaking notifications" on public.matchmaking_notifications;
create policy "Users read own matchmaking notifications"
  on public.matchmaking_notifications for select to authenticated
  using (recipient_id = (select auth.uid()));
drop policy if exists "Users mark own matchmaking notifications read" on public.matchmaking_notifications;
create policy "Users mark own matchmaking notifications read"
  on public.matchmaking_notifications for update to authenticated
  using (recipient_id = (select auth.uid()))
  with check (recipient_id = (select auth.uid()));

create or replace function public.notify_matchmaking_host_on_opponent_join()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_host uuid;
  v_title text;
  v_venue text;
  v_date date;
  v_time time;
  v_team_name text;
begin
  if new.status <> 'joined' or (tg_op = 'UPDATE' and old.status = 'joined') then
    return new;
  end if;
  select host_id, title, venue, session_date, start_time
    into v_host, v_title, v_venue, v_date, v_time
  from public.matchmaking_sessions where id = new.session_id;
  if v_host is not null and new.player_id <> v_host then
    v_team_name := coalesce(nullif(trim(new.team_name), ''), 'Tim lawan');
    insert into public.matchmaking_notifications(recipient_id, session_id, message)
    values (
      v_host, new.session_id,
      'Tim ' || v_team_name || ' memilih tantangan sparing tim kamu: ' || v_title || ' di ' || v_venue ||
      ' pada ' || to_char(v_date, 'DD Mon YYYY') || ' pukul ' || to_char(v_time, 'HH24:MI') || '.'
    );
  end if;
  return new;
end;
$$;
drop trigger if exists notify_matchmaking_host_on_join on public.matchmaking_players;
create trigger notify_matchmaking_host_on_join
after insert or update of status on public.matchmaking_players
for each row execute function public.notify_matchmaking_host_on_opponent_join();

drop function if exists public.get_matchmaking_sessions();
create function public.get_matchmaking_sessions()
returns table (
  id uuid, host_id uuid, title text, venue text, session_date date, start_time time,
  duration_hours integer, skill_level text, max_players integer, notes text, status text,
  created_at timestamptz, joined_count bigint, opponent_joined boolean, opponent_team_name text
)
language sql stable security definer set search_path = ''
as $$
  select s.id, s.host_id, s.title, s.venue, s.session_date, s.start_time,
    s.duration_hours, s.skill_level, s.max_players, s.notes, s.status, s.created_at,
    (select count(*) from public.matchmaking_players mp
      where mp.session_id = s.id and mp.status = 'joined') as joined_count,
    exists (select 1 from public.matchmaking_players mp
      where mp.session_id = s.id and mp.status = 'joined' and mp.player_id <> s.host_id) as opponent_joined,
    (select mp.team_name from public.matchmaking_players mp
      where mp.session_id = s.id and mp.status = 'joined' and mp.player_id <> s.host_id limit 1) as opponent_team_name
  from public.matchmaking_sessions s
  where s.status in ('open','full') and s.session_date >= current_date
  order by s.session_date, s.start_time;
$$;

drop function if exists public.join_matchmaking_session(uuid);
create function public.join_matchmaking_session(p_session_id uuid, p_team_name text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.matchmaking_sessions%rowtype;
  v_existing text;
  v_team_name text := nullif(trim(coalesce(p_team_name, '')), '');
begin
  if (select auth.uid()) is null then raise exception 'Silakan login untuk memilih jadwal sparing'; end if;
  if v_team_name is null or length(v_team_name) > 100 then raise exception 'Nama tim wajib diisi (maksimal 100 karakter)'; end if;
  select * into v_session from public.matchmaking_sessions where id = p_session_id for update;
  if not found then raise exception 'Jadwal sparing tidak ditemukan'; end if;
  if v_session.status <> 'open' then raise exception 'Jadwal ini sudah tidak terbuka'; end if;
  if v_session.host_id = (select auth.uid()) then raise exception 'Kamu tidak bisa memilih jadwal tim sendiri'; end if;
  select status into v_existing from public.matchmaking_players
    where session_id = p_session_id and player_id = (select auth.uid());
  if v_existing = 'joined' then return 'already_joined'; end if;
  if exists (
    select 1 from public.matchmaking_players mp
    where mp.session_id = p_session_id and mp.status = 'joined' and mp.player_id <> v_session.host_id
  ) then raise exception 'Jadwal ini sudah dipilih tim lain'; end if;
  insert into public.matchmaking_players(session_id, player_id, team_name, status)
  values (p_session_id, (select auth.uid()), v_team_name, 'joined')
  on conflict (session_id, player_id) do update
    set status = 'joined', team_name = excluded.team_name;
  return 'joined';
end;
$$;

grant execute on function public.get_matchmaking_sessions() to anon, authenticated;
grant execute on function public.join_matchmaking_session(uuid, text) to authenticated;

-- Enable realtime delivery for in-app host notifications when the publication exists.
do $realtime$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'matchmaking_notifications'
     ) then
    execute 'alter publication supabase_realtime add table public.matchmaking_notifications';
  end if;
end;
$realtime$;
commit;
