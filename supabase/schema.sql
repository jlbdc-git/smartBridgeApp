-- ============================================================================
--  SmartBridge Messages - Supabase schema
-- ============================================================================
--  Run this ONCE in the Supabase dashboard: SQL Editor -> New query -> Run.
--  Then run `policies.sql` in the same way.
--
--  DESIGN RULES (these come from the product spec, not from taste):
--   * Users must meet in person: a connection always starts from a QR code or
--     a short code. There is deliberately NO searchable user directory and no
--     endpoint that lists users.
--   * Only confirmed friends may exchange messages.
--   * No unnecessary personal data: an anonymous auth identity, a display
--     name, a role and nothing else. No email, phone, location or contacts.
--   * Row level security is the ONLY authorization boundary. The mobile app
--     holds no privileged credential (see backend_config.dart, which refuses
--     to start if a service-role key is compiled in by mistake).
--
--  Identifiers:
--   * profiles.id   = auth.uid() (the Supabase user id)
--   * messages.id   = generated ON THE CLIENT, so that a retry after a lost
--                     response cannot create a duplicate message.
-- ============================================================================

-- Needed for gen_random_uuid().
create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- profiles: one row per device/user
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id               uuid primary key references auth.users (id) on delete cascade,
  display_name     text        not null
                     check (char_length(display_name) between 1 and 60),
  role             text        not null check (role in ('blind', 'deaf')),

  -- The short code this user shows to a friend. Unique so a code always
  -- identifies exactly one person; rotating it does not affect friendships.
  invite_code      text        unique,
  invite_issued_at timestamptz,

  -- Heartbeat used as a lightweight "is this friend reachable now?" signal.
  last_seen_at     timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

comment on table public.profiles is
  'One row per user. Contains only a display name, a role and the rotating '
  'invite code - no contact details are collected anywhere in this app.';

-- ---------------------------------------------------------------------------
-- friendships: an explicit request + confirmation pair
-- ---------------------------------------------------------------------------
-- Deliberately NOT canonicalised into (min,max) pairs: keeping the direction
-- lets the addressee's device subscribe to inbound requests with a single
-- realtime filter, and the confirmation is what authorises messaging.
create table if not exists public.friendships (
  id           uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles (id) on delete cascade,
  addressee_id uuid not null references public.profiles (id) on delete cascade,
  status       text not null default 'pending'
                 check (status in ('pending', 'confirmed')),
  created_at   timestamptz not null default now(),
  confirmed_at timestamptz,

  constraint friendships_not_self check (requester_id <> addressee_id),
  constraint friendships_unique_pair unique (requester_id, addressee_id)
);

create index if not exists friendships_addressee_idx
  on public.friendships (addressee_id);
create index if not exists friendships_requester_idx
  on public.friendships (requester_id);

-- ---------------------------------------------------------------------------
-- messages
-- ---------------------------------------------------------------------------
create table if not exists public.messages (
  -- Client generated: makes uploads idempotent under retry.
  id               text primary key,
  sender_id        uuid not null references public.profiles (id) on delete cascade,
  receiver_id      uuid not null references public.profiles (id) on delete cascade,

  -- Denormalised so realtime payloads can render a conversation without a
  -- second round trip (and without needing to read the peer's profile row).
  sender_name      text not null,

  original_text    text not null,   -- exactly what the user said / typed
  translated_text  text not null,   -- what actually travels
  direction        text not null
                     check (direction in ('blindToDeaf', 'deafToBlind')),

  -- Manually chosen by a Deaf sender. Never inferred (no emotion detection).
  emotion          text check (emotion in ('happy', 'sad', 'angry', 'shy')),

  transcription    text,
  created_at       timestamptz not null,
  read_at          timestamptz,

  constraint messages_not_self check (sender_id <> receiver_id)
);

create index if not exists messages_receiver_created_idx
  on public.messages (receiver_id, created_at desc);
create index if not exists messages_sender_receiver_idx
  on public.messages (sender_id, receiver_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Helper: are these two users confirmed friends?
-- ---------------------------------------------------------------------------
-- SECURITY DEFINER so the policy checks below can consult `friendships`
-- without recursing into that table's own policies (the classic RLS
-- self-reference trap).
create or replace function public.are_confirmed_friends(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.friendships f
    where f.status = 'confirmed'
      and (
        (f.requester_id = a and f.addressee_id = b)
        or (f.requester_id = b and f.addressee_id = a)
      )
  );
$$;

revoke all on function public.are_confirmed_friends(uuid, uuid) from public;
grant execute on function public.are_confirmed_friends(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- RPC: exact-match invite-code lookup
-- ---------------------------------------------------------------------------
-- This is the ONLY way one user can discover another. It takes the exact code
-- and returns at most one row. There is no prefix search, no listing and no
-- way to enumerate the user base.
--
-- It refuses codes that are expired, and refuses to hand out an identity to
-- somebody who is already a confirmed friend (nothing to gain, and it narrows
-- the surface for probing).
create or replace function public.lookup_invite_code(p_code text)
returns table (
  peer_id      uuid,
  display_name text,
  role         text,
  is_expired   boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    return;
  end if;

  return query
    select p.id,
           p.display_name,
           p.role,
           (p.invite_issued_at is null
             or p.invite_issued_at < now() - interval '30 minutes')
    from public.profiles p
    where p.invite_code = upper(trim(p_code))
      and p.id <> me
    limit 1;
end;
$$;

revoke all on function public.lookup_invite_code(text) from public;
grant execute on function public.lookup_invite_code(text) to authenticated;

-- ---------------------------------------------------------------------------
-- RPC: request a friendship using somebody's code
-- ---------------------------------------------------------------------------
-- Creates (or revives) a PENDING friendship. It can never create a confirmed
-- friendship on its own: the code owner still has to call
-- confirm_friendship() from their own authenticated session.
create or replace function public.request_friendship(p_code text)
returns table (
  peer_id      uuid,
  display_name text,
  role         text,
  status       text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  me        uuid := auth.uid();
  target    public.profiles%rowtype;
  existing  public.friendships%rowtype;
begin
  if me is null then
    return;
  end if;

  select *
    into target
    from public.profiles p
   where p.invite_code = upper(trim(p_code))
     and p.id <> me
     and p.invite_issued_at is not null
     and p.invite_issued_at >= now() - interval '30 minutes'
   limit 1;

  if not found then
    return;                       -- unknown or expired code
  end if;

  -- Already connected in either direction?
  select *
    into existing
    from public.friendships f
   where (f.requester_id = me and f.addressee_id = target.id)
      or (f.requester_id = target.id and f.addressee_id = me)
   limit 1;

  if found then
    return query
      select target.id, target.display_name, target.role, existing.status;
    return;
  end if;

  insert into public.friendships (requester_id, addressee_id, status)
  values (me, target.id, 'pending');

  return query
    select target.id, target.display_name, target.role, 'pending'::text;
end;
$$;

revoke all on function public.request_friendship(text) from public;
grant execute on function public.request_friendship(text) to authenticated;

-- ---------------------------------------------------------------------------
-- RPC: confirm a pending friendship (only the addressee may do this)
-- ---------------------------------------------------------------------------
create or replace function public.confirm_friendship(p_friendship_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  me      uuid := auth.uid();
  updated integer;
begin
  if me is null then
    return false;
  end if;

  update public.friendships f
     set status = 'confirmed',
         confirmed_at = now()
   where f.id = p_friendship_id
     and f.addressee_id = me          -- only the invited side can accept
     and f.status = 'pending';

  get diagnostics updated = row_count;
  return updated > 0;
end;
$$;

revoke all on function public.confirm_friendship(uuid) from public;
grant execute on function public.confirm_friendship(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- RPC: end a friendship
-- ---------------------------------------------------------------------------
-- Removing a friend must actually revoke access, on both sides. The other
-- person keeps the messages already delivered (they are on their device), but
-- can no longer read or send anything from that point on.
create or replace function public.revoke_friendship(p_other uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  me      uuid := auth.uid();
  deleted integer;
begin
  if me is null then
    return false;
  end if;

  delete from public.friendships f
   where (f.requester_id = me and f.addressee_id = p_other)
      or (f.requester_id = p_other and f.addressee_id = me);

  get diagnostics deleted = row_count;
  return deleted > 0;
end;
$$;

revoke all on function public.revoke_friendship(uuid) from public;
grant execute on function public.revoke_friendship(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- updated_at maintenance
-- ---------------------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists profiles_touch_updated_at on public.profiles;
create trigger profiles_touch_updated_at
  before update on public.profiles
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Realtime
-- ---------------------------------------------------------------------------
-- `messages` powers live delivery, `friendships` powers inbound connection
-- requests, `profiles` powers the friend-reachability heartbeat. Realtime
-- honours RLS, so a user only ever receives rows they may already read.
--
-- Guarded because `ALTER PUBLICATION ... ADD TABLE` raises if the table is
-- already published, which would make this script fail on a second run.
do $$
declare
  t text;
begin
  foreach t in array array['messages', 'friendships', 'profiles'] loop
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end;
$$;
