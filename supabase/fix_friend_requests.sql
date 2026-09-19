-- ============================================================================
--  SmartBridge Messages - friend request upgrade (run on the LIVE project)
-- ============================================================================
--  Supabase dashboard -> SQL Editor -> New query -> paste -> Run.
--  Idempotent: safe to re-run. No data is deleted. RLS stays fully enabled.
--
--  WHY THIS EXISTS
--  ---------------
--  1) The messages INSERT policy is CORRECT: it only allows a message when a
--     CONFIRMED friendship row exists between the two users. The 42501
--     "new row violates row-level security policy" seen in production was
--     caused by the app treating a merely PENDING request as a friendship:
--     the sender's device uploaded messages before the other side accepted.
--     The fix is in the app flow (send nothing until confirmed) - NOT in the
--     policy, which stays exactly as strict as before.
--
--  2) The request flow needed real decline/re-list support:
--       * a declined request must not deadlock the pair (before, both sides
--         could stay blocked forever),
--       * two people who both add each other must not create two opposite
--         pending rows that neither can act on - the second request now
--         auto-confirms (mutual intent),
--       * the Friend Requests section must survive an app restart, so the
--         pending list is now fetchable (list_my_requests RPC), not only
--         delivered via realtime events.
--
--  WHAT THE APP DOES WITH THIS
--  ---------------------------
--    A enters B's code -> request_friendship  -> row (requester A, addressee B)
--    B opens Friend Requests -> sees the request (who/role/when)
--       Accept  -> confirm_friendship()  -> status confirmed -> both chat
--       Decline -> decline_friendship()  -> status declined  -> chat stays shut
--    A re-requesting later revives a declined row (status back to pending).
--    B requesting A while A's request is still pending auto-confirms instead
--    of creating a duplicate reverse row.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Table shape: allow 'declined'
-- ---------------------------------------------------------------------------

-- The original inline check constraint is auto-named friendships_status_check.
alter table public.friendships drop constraint if exists friendships_status_check;
alter table public.friendships
  add constraint friendships_status_check
  check (status in ('pending', 'confirmed', 'declined'));

alter table public.friendships
  add column if not exists declined_at timestamptz;

-- ---------------------------------------------------------------------------
-- 2. request_friendship: idempotent, mutual-safe, revive-after-decline
-- ---------------------------------------------------------------------------
-- Returns the peer and the resulting status so the app never has to guess:
--   'confirmed'  already friends (nothing to do, add locally)
--   'pending'    request stored / revived; wait for the other side to accept
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
     and p.id <> me                      -- can never request yourself
     and p.invite_issued_at is not null
     and p.invite_issued_at >= now() - interval '30 minutes'
   limit 1;

  if not found then
    return;                              -- unknown or expired code
  end if;

  -- Any existing row between us (either direction)?
  select *
    into existing
    from public.friendships f
   where (f.requester_id = me and f.addressee_id = target.id)
      or (f.requester_id = target.id and f.addressee_id = me)
   limit 1;

  if found then
    if existing.status = 'confirmed' then
      -- Already friends: report it, change nothing.
      return query
        select target.id, target.display_name, target.role, 'confirmed'::text;
      return;
    end if;

    if existing.status = 'pending'
       and existing.requester_id = target.id then
      -- They already invited me and I am now inviting them: that is mutual
      -- intent, so confirm on the spot instead of deadlocking on two
      -- opposite pending rows.
      update public.friendships
         set status = 'confirmed',
             confirmed_at = now(),
             declined_at = null
       where id = existing.id;
      return query
        select target.id, target.display_name, target.role, 'confirmed'::text;
      return;
    end if;

    if existing.status = 'pending' then
      -- I already have a pending request out. Idempotent: no duplicate.
      return query
        select target.id, target.display_name, target.role, 'pending'::text;
      return;
    end if;

    -- status = 'declined': my request replaces the old one. The row keeps a
    -- single direction (mine now), so the other side sees a fresh request.
    update public.friendships
       set requester_id = me,
           addressee_id = target.id,
           status = 'pending',
           declined_at = null,
           created_at = now(),
           confirmed_at = null
     where id = existing.id;
    return query
      select target.id, target.display_name, target.role, 'pending'::text;
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
-- 3. decline_friendship: only the invited side, only pending rows
-- ---------------------------------------------------------------------------
create or replace function public.decline_friendship(p_friendship_id uuid)
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
     set status = 'declined',
         declined_at = now()
   where f.id = p_friendship_id
     and f.addressee_id = me             -- only the invited side may decline
     and f.status = 'pending';

  get diagnostics updated = row_count;
  return updated > 0;
end;
$$;

revoke all on function public.decline_friendship(uuid) from public;
grant execute on function public.decline_friendship(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. list_my_requests: powers the Friend Requests section
-- ---------------------------------------------------------------------------
-- Returns every friendship row I am part of, with the peer's public profile
-- (display name + role only - the same fields a QR code already exposes).
-- The client splits it into incoming pending / outgoing pending / declined /
-- confirmed. Confirmed rows are also how a device reconciles friendships it
-- accepted on another device or while this app was closed.
create or replace function public.list_my_requests()
returns table (
  friendship_id uuid,
  direction     text,      -- 'incoming' = I was invited, 'outgoing' = I invited
  status        text,
  peer_id       uuid,
  peer_name     text,
  peer_role     text,
  requested_at  timestamptz
)
language sql
security definer
set search_path = public
as $$
  select f.id,
         case when f.addressee_id = (select auth.uid())
              then 'incoming' else 'outgoing' end,
         f.status,
         p.id,
         p.display_name,
         p.role,
         f.created_at
    from public.friendships f
    join public.profiles p
      on p.id = case
                  when f.addressee_id = (select auth.uid()) then f.requester_id
                  else f.addressee_id
                end
   where f.addressee_id = (select auth.uid())
      or f.requester_id  = (select auth.uid())
   order by f.created_at desc;
$$;

revoke all on function public.list_my_requests() from public;
grant execute on function public.list_my_requests() to authenticated;

-- ---------------------------------------------------------------------------
-- 5. What did NOT change (on purpose)
-- ---------------------------------------------------------------------------
--  * messages RLS: still only "sender = me AND receiver is a CONFIRMED
--    friend". The app now respects this instead of fighting it.
--  * confirm_friendship: addressee-only, pending -> confirmed. Unchanged.
--  * revoke_friendship: deletes rows in both directions (remove friend or
--    cancel my own pending request). Unchanged.
--  * RLS stays enabled on every table; nothing is granted to `anon`.
--  * The 'declined' status only ever blocks; it never grants message access.
