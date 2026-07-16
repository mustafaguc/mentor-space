-- Onboarding upserts the caller's own profile row. PostgREST upsert issues
-- INSERT ... ON CONFLICT, so RLS requires an INSERT policy even though the row
-- (created by handle_new_user) already exists and the statement resolves to an
-- UPDATE. Without this, saving the role fails with a row-level-security error.
drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own on public.profiles
  for insert with check (auth.uid() = id);
