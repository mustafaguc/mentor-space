-- ============================================================================
-- device_tokens: one row per device push token (FCM). Used by the notify-call
-- Edge Function to wake a mentor's device for an incoming call, even when the
-- app is backgrounded or killed (Supabase Realtime can't reach a killed app).
--
-- `token` is the PRIMARY KEY (globally unique per device) so that when a
-- different user signs in on the same device, the token is re-assigned to them
-- (on conflict update) instead of leaving the previous user still reachable.
-- ============================================================================
create table if not exists public.device_tokens (
  token      text primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  platform   text not null default 'android',
  updated_at timestamptz not null default now()
);

create index if not exists device_tokens_user_idx on public.device_tokens(user_id);

alter table public.device_tokens enable row level security;

-- A user may read/write only their own tokens. The notify-call function reads
-- *other* users' tokens through the service role, which bypasses RLS.
drop policy if exists device_tokens_select_own on public.device_tokens;
create policy device_tokens_select_own on public.device_tokens
  for select using (auth.uid() = user_id);

drop policy if exists device_tokens_insert_own on public.device_tokens;
create policy device_tokens_insert_own on public.device_tokens
  for insert with check (auth.uid() = user_id);

drop policy if exists device_tokens_update_own on public.device_tokens;
create policy device_tokens_update_own on public.device_tokens
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists device_tokens_delete_own on public.device_tokens;
create policy device_tokens_delete_own on public.device_tokens
  for delete using (auth.uid() = user_id);
