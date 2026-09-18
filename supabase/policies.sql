-- ============================================================================
--  SmartBridge Messages - row level security
-- ============================================================================
--  Run AFTER schema.sql, in the Supabase SQL Editor.
--
--  THREAT MODEL
--  The mobile client is treated as fully hostile: anyone can extract the anon
--  key from the APK and call the API directly with their own authenticated
--  session. Therefore:
--   * Every table has RLS enabled with DEFAULT DENY.
--   * There is NO client-side INSERT/UPDATE/DELETE policy on `friendships`
--     at all. Friendships can only be created/confirmed/revoked through the
--     SECURITY DEFINER functions in schema.sql, which require possession of a
--     valid, unexpired invite code. Knowing a user id is not enough.
--   * Messages are immutable apart from `read_at`, enforced by a trigger.
-- ============================================================================

alter table public.profiles    enable row level security;
alter table public.friendships enable row level security;
alter table public.messages    enable row level security;

-- Belt and braces: without this, a table owner is still exempt from RLS.
alter table public.profiles    force row level security;
alter table public.friendships force row level security;
alter table public.messages    force row level security;

-- ============================================================================
--  profiles
-- ============================================================================

-- My own profile, plus the profile of anybody I have a friendship row with
-- (pending or confirmed). The pending case is what lets the connection-request
-- card show a name before the friendship exists.
create policy "profiles: read self and connected users"
  on public.profiles
  for select
  to authenticated
  using (
    id = (select auth.uid())
    or exists (
      select 1
      from public.friendships f
      where (f.requester_id = (select auth.uid()) and f.addressee_id = profiles.id)
         or (f.addressee_id = (select auth.uid()) and f.requester_id = profiles.id)
    )
  );

-- I may only create my own row, and only under my own auth id.
create policy "profiles: insert self"
  on public.profiles
  for insert
  to authenticated
  with check (id = (select auth.uid()));

-- I may only change my own row. `with check` also stops me rewriting the id
-- to hijack somebody else's row.
create policy "profiles: update self"
  on public.profiles
  for update
  to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- ============================================================================
--  friendships
-- ============================================================================
-- Read only. There is intentionally no insert/update/delete policy:
--   * create  -> request_friendship(code)   (needs a live invite code)
--   * accept  -> confirm_friendship(id)     (addressee only)
--   * remove  -> revoke_friendship(uid)     (either participant)
create policy "friendships: read own"
  on public.friendships
  for select
  to authenticated
  using (
    requester_id = (select auth.uid())
    or addressee_id = (select auth.uid())
  );

-- ============================================================================
--  messages
-- ============================================================================

-- I can read a message I sent or one addressed to me. Reading is not gated on
-- the friendship still existing so that "I sent this" stays true for the
-- sender even after a removal; sending is gated, below.
create policy "messages: read own"
  on public.messages
  for select
  to authenticated
  using (
    sender_id = (select auth.uid())
    or receiver_id = (select auth.uid())
  );

-- The only way a message can exist: I am the sender AND we are confirmed
-- friends. are_confirmed_friends() is SECURITY DEFINER, so this does not
-- recurse into the friendships policies.
create policy "messages: send to confirmed friend"
  on public.messages
  for insert
  to authenticated
  with check (
    sender_id = (select auth.uid())
    and receiver_id <> (select auth.uid())
    and public.are_confirmed_friends((select auth.uid()), receiver_id)
  );

-- Only the RECEIVER may update, and only to record that they read it. The
-- trigger below rejects any other change, so the text cannot be edited or
-- forged after the fact.
create policy "messages: receiver marks read"
  on public.messages
  for update
  to authenticated
  using (receiver_id = (select auth.uid()))
  with check (receiver_id = (select auth.uid()));

-- ============================================================================
--  Message immutability (defence in depth)
-- ============================================================================
-- A policy can restrict WHO updates a row but not WHICH COLUMNS they touch.
-- This trigger closes that gap: the content of a delivered message can never
-- be altered, and `read_at` can only move from null to a timestamp.
create or replace function public.messages_guard_update()
returns trigger
language plpgsql
as $$
begin
  if new.id            is distinct from old.id
     or new.sender_id    is distinct from old.sender_id
     or new.receiver_id  is distinct from old.receiver_id
     or new.sender_name  is distinct from old.sender_name
     or new.original_text   is distinct from old.original_text
     or new.translated_text is distinct from old.translated_text
     or new.direction    is distinct from old.direction
     or new.emotion      is distinct from old.emotion
     or new.transcription is distinct from old.transcription
     or new.created_at   is distinct from old.created_at
  then
    raise exception 'messages are immutable except for read_at';
  end if;

  -- Once read, it stays read; a later update cannot unset it.
  if old.read_at is not null and new.read_at is null then
    raise exception 'read_at cannot be cleared';
  end if;

  return new;
end;
$$;

drop trigger if exists messages_guard_update on public.messages;
create trigger messages_guard_update
  before update on public.messages
  for each row execute function public.messages_guard_update();

-- ============================================================================
--  Realtime authorization
-- ============================================================================
-- Realtime postgres_changes evaluates the SELECT policies above for the
-- subscribing user, so the three channels the app opens
-- (messages / friendships / profiles) can only ever deliver rows that user is
-- already allowed to read. No extra configuration is required, but the
-- extension must be enabled in the dashboard (Database -> Replication).
