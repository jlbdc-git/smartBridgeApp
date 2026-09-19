-- ============================================================================
--  SmartBridge Messages - FIX for live errors
--      42501  permission denied for table friendships / profiles
--      P0001  invalid column for filter addressee_id / receiver_id
-- ============================================================================
--  WHERE TO RUN: Supabase dashboard -> SQL Editor -> New query -> paste -> Run.
--  Safe to re-run: every statement is idempotent. No data is touched.
--
--  WHY THIS IS NEEDED
--  ------------------
--  1) 42501: since the May 2026 platform change, new tables in `public` are
--     NOT exposed to the Data API unless the project owner grants access
--     explicitly. `create table` alone is no longer enough: the anon and
--     authenticated roles need real GRANTs. This matches the Supabase
--     changelog entry "Tables not exposed to Data and GraphQL API
--     automatically" (April 2026) and its hint:
--         GRANT SELECT ON public.your_table TO anon;
--
--  2) P0001: Realtime validates a channel filter by actually querying the
--     table. The realtime reader role ("supabase_realtime_admin") needs
--     SELECT on the table; without it, validation fails and the channel is
--     rejected with "invalid column for filter <col>" even though the column
--     exists. It also needs the table in the supabase_realtime publication
--     (schema.sql adds that, and this script re-asserts it).
--
--  No new privileges exceed what the app needs. RLS stays enabled and forced
--  on every table, so these grants only allow the REQUEST to reach the
--  database - row level security still decides which rows come back.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. API access for the client roles
-- ---------------------------------------------------------------------------

-- anon: only used to reach auth endpoints; keep table access nil.
-- (Nothing granted to anon below - listed here so the intent is explicit.)

-- authenticated: the role every device session actually uses.
grant select, insert, update on public.profiles    to authenticated;
grant select, insert, update on public.messages    to authenticated;
grant select                 on public.friendships to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Realtime reader access (fixes P0001 "invalid column for filter")
-- ---------------------------------------------------------------------------

grant select on public.profiles    to supabase_realtime_admin;
grant select on public.friendships to supabase_realtime_admin;
grant select on public.messages    to supabase_realtime_admin;

-- ---------------------------------------------------------------------------
-- 3. Ensure the tables are published for postgres_changes
-- ---------------------------------------------------------------------------
-- schema.sql guards this with an existence check; this block re-asserts it so
-- this script alone is sufficient on a project where schema.sql was run
-- before this problem appeared.

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

-- ---------------------------------------------------------------------------
-- 4. Verify (run the SELECTs one by one in the SQL editor if you like)
-- ---------------------------------------------------------------------------
--
--  -- a) Who may touch each table?
--  select grantee, table_name, privilege_type
--    from information_schema.role_table_grants
--   where table_schema = 'public'
--     and table_name in ('profiles', 'friendships', 'messages')
--   order by table_name, grantee;
--
--  -- b) Are the tables published?
--  select tablename from pg_publication_tables
--   where pubname = 'supabase_realtime' and schemaname = 'public';
--
--  -- c) RLS really on?
--  select relname, relrowsecurity, relforcerowsecurity
--    from pg_class
--   where relnamespace = 'public'::regnamespace
--     and relname in ('profiles', 'friendships', 'messages');
