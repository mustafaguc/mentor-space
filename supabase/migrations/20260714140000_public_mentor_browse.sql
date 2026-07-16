-- Public discovery: let anonymous visitors browse mentor profiles so they can
-- explore by category before signing in. Login is only needed to start a call.
--
-- Two permissive SELECT policies (OR'd):
--   * anyone (anon or authed) may read rows where role = 'mentor'
--   * authenticated users may read all profiles (needed for name lookups, e.g.
--     the mentor resolving who is calling them)
-- Profiles hold no sensitive data (no email/phone), only public marketplace info.

drop policy if exists profiles_read on public.profiles;

drop policy if exists profiles_read_mentors_public on public.profiles;
create policy profiles_read_mentors_public on public.profiles
  for select using (role = 'mentor');

drop policy if exists profiles_read_authenticated on public.profiles;
create policy profiles_read_authenticated on public.profiles
  for select using (auth.role() = 'authenticated');

-- Ensure the anon role has table-level SELECT (RLS still gates rows above).
grant select on public.profiles to anon;
