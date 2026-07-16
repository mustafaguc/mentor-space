-- ============================================================================
-- Mentora — database schema
-- Run this in your Supabase project:  SQL Editor -> New query -> paste -> Run
-- Safe to re-run (idempotent-ish; drops policies before recreating).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- profiles: 1 row per auth user. Extends auth.users with app data.
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id              uuid primary key references auth.users(id) on delete cascade,
  full_name       text,
  -- role is NULL until the user picks it in onboarding (same flow for everyone).
  role            text check (role in ('client','mentor')),
  headline        text,                       -- e.g. "Cardiologist", "Tax lawyer"
  bio             text,
  sector          text,                       -- education | health | law | tech | agriculture | services
  coins_per_minute integer not null default 0 check (coins_per_minute >= 0),
  avatar_url      text,
  is_online       boolean not null default false,
  last_seen       timestamptz,
  created_at      timestamptz not null default now()
);

-- If profiles already existed with the old NOT NULL / default 'client' role,
-- relax it so role can stay NULL until the user chooses in onboarding.
alter table public.profiles alter column role drop default;
alter table public.profiles alter column role drop not null;

-- ---------------------------------------------------------------------------
-- wallets: coin balance per user
-- ---------------------------------------------------------------------------
create table if not exists public.wallets (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  balance    integer not null default 0 check (balance >= 0),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- sessions: one row per call/session
-- ---------------------------------------------------------------------------
create table if not exists public.sessions (
  id          uuid primary key default gen_random_uuid(),
  room_id     text not null,                  -- Jitsi room name both parties join
  client_id   uuid not null references auth.users(id) on delete cascade,
  mentor_id   uuid not null references auth.users(id) on delete cascade,
  status      text not null default 'pending'
              check (status in ('pending','active','ended','rejected','missed')),
  started_at  timestamptz,
  ended_at    timestamptz,
  coins_spent integer not null default 0,
  created_at  timestamptz not null default now()
);

create index if not exists sessions_mentor_idx on public.sessions(mentor_id);
create index if not exists sessions_client_idx on public.sessions(client_id);

-- ---------------------------------------------------------------------------
-- transactions: append-only coin ledger
-- ---------------------------------------------------------------------------
create table if not exists public.transactions (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  amount      integer not null,               -- + credit, - debit
  type        text not null check (type in ('topup','spend','earn','refund')),
  session_id  uuid references public.sessions(id) on delete set null,
  created_at  timestamptz not null default now()
);

create index if not exists transactions_user_idx on public.transactions(user_id);

-- ---------------------------------------------------------------------------
-- Auto-provision profile + wallet when a new auth user is created.
-- Reads optional metadata passed at signup (full_name, role).
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  -- Role is intentionally left NULL — the app's onboarding step sets it, so
  -- clients and mentors share one identical sign-in flow. Name/avatar are
  -- pulled from the OAuth identity when present (Google/Apple), else blank.
  insert into public.profiles (id, full_name, avatar_url, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', ''),
    coalesce(new.raw_user_meta_data->>'avatar_url', new.raw_user_meta_data->>'picture'),
    new.raw_user_meta_data->>'role'
  )
  on conflict (id) do nothing;

  insert into public.wallets (user_id, balance)
  values (new.id, 100)                          -- 100 free coins to start
  on conflict (user_id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.profiles     enable row level security;
alter table public.wallets      enable row level security;
alter table public.sessions     enable row level security;
alter table public.transactions enable row level security;

-- profiles: everyone signed in can read (needed to browse mentors);
--           you can only edit your own row.
drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles
  for select using (auth.role() = 'authenticated');

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);

-- wallets: you can only see your own balance.
drop policy if exists wallets_read_own on public.wallets;
create policy wallets_read_own on public.wallets
  for select using (auth.uid() = user_id);

-- sessions: you can see sessions you're part of, and create sessions where
--           you are the client.
drop policy if exists sessions_read_own on public.sessions;
create policy sessions_read_own on public.sessions
  for select using (auth.uid() = client_id or auth.uid() = mentor_id);

drop policy if exists sessions_insert_client on public.sessions;
create policy sessions_insert_client on public.sessions
  for insert with check (auth.uid() = client_id);

drop policy if exists sessions_update_participant on public.sessions;
create policy sessions_update_participant on public.sessions
  for update using (auth.uid() = client_id or auth.uid() = mentor_id);

-- transactions: read-only view of your own ledger.
--   NOTE: writes to wallets/transactions happen through a SECURITY DEFINER
--   function (see spend_coins below), never directly from the client, so
--   balances can't be tampered with.
drop policy if exists transactions_read_own on public.transactions;
create policy transactions_read_own on public.transactions
  for select using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- spend_coins: atomically move coins from client -> mentor for a session.
-- Called via RPC. Runs as definer so it can update wallets despite RLS.
-- ---------------------------------------------------------------------------
create or replace function public.spend_coins(
  p_session_id uuid,
  p_amount     integer
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_client uuid;
  v_mentor uuid;
  v_balance integer;
begin
  if p_amount <= 0 then
    raise exception 'amount must be positive';
  end if;

  select client_id, mentor_id into v_client, v_mentor
  from public.sessions where id = p_session_id;

  if v_client is null then
    raise exception 'session not found';
  end if;

  -- only the client of the session may trigger the charge
  if auth.uid() <> v_client then
    raise exception 'not authorized';
  end if;

  select balance into v_balance from public.wallets where user_id = v_client for update;
  if v_balance < p_amount then
    raise exception 'insufficient balance';
  end if;

  update public.wallets set balance = balance - p_amount, updated_at = now()
    where user_id = v_client;
  update public.wallets set balance = balance + p_amount, updated_at = now()
    where user_id = v_mentor;

  insert into public.transactions (user_id, amount, type, session_id)
    values (v_client, -p_amount, 'spend', p_session_id),
           (v_mentor,  p_amount, 'earn',  p_session_id);

  update public.sessions
    set coins_spent = coins_spent + p_amount
    where id = p_session_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- topup_coins: add coins to the caller's own wallet + log the transaction.
-- MVP stand-in for a real payment provider (Stripe/IAP) — swap the caller for
-- a verified-purchase webhook later; the ledger stays the same.
-- ---------------------------------------------------------------------------
create or replace function public.topup_coins(p_amount integer)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if p_amount <= 0 then
    raise exception 'amount must be positive';
  end if;

  insert into public.wallets (user_id, balance)
    values (v_uid, p_amount)
    on conflict (user_id) do update
      set balance = public.wallets.balance + excluded.balance,
          updated_at = now();

  insert into public.transactions (user_id, amount, type)
    values (v_uid, p_amount, 'topup');
end;
$$;

-- ===========================================================================
-- RATINGS — clients rate mentors after a session.
-- Each mentor carries a denormalised rating_avg / rating_count on their
-- profile (kept in sync by a trigger) so the mentor list stays cheap to read.
-- ===========================================================================

alter table public.profiles
  add column if not exists rating_avg numeric(3,2) not null default 0;
alter table public.profiles
  add column if not exists rating_count integer not null default 0;

create table if not exists public.ratings (
  id         uuid primary key default gen_random_uuid(),
  session_id uuid not null unique references public.sessions(id) on delete cascade,
  mentor_id  uuid not null references auth.users(id) on delete cascade,
  client_id  uuid not null references auth.users(id) on delete cascade,
  stars      integer not null check (stars between 1 and 5),
  comment    text,
  created_at timestamptz not null default now()
);

create index if not exists ratings_mentor_idx on public.ratings(mentor_id);

-- Recompute the mentor's aggregate whenever their ratings change.
create or replace function public.recompute_mentor_rating()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_mentor uuid := coalesce(new.mentor_id, old.mentor_id);
begin
  update public.profiles p set
    rating_count = (select count(*) from public.ratings r where r.mentor_id = v_mentor),
    rating_avg   = coalesce((select avg(stars) from public.ratings r where r.mentor_id = v_mentor), 0)
  where p.id = v_mentor;
  return null;
end;
$$;

drop trigger if exists on_rating_change on public.ratings;
create trigger on_rating_change
  after insert or update or delete on public.ratings
  for each row execute function public.recompute_mentor_rating();

alter table public.ratings enable row level security;

-- Anyone signed in can read reviews.
drop policy if exists ratings_read on public.ratings;
create policy ratings_read on public.ratings
  for select using (auth.role() = 'authenticated');

-- A client may rate only a session they actually took part in as the client,
-- and only for that session's mentor. UNIQUE(session_id) => one rating/session.
drop policy if exists ratings_insert_client on public.ratings;
create policy ratings_insert_client on public.ratings
  for insert with check (
    auth.uid() = ratings.client_id
    and exists (
      select 1 from public.sessions s
      where s.id = ratings.session_id
        and s.client_id = ratings.client_id
        and s.mentor_id = ratings.mentor_id
    )
  );

-- ===========================================================================
-- REALTIME — the mentor's "incoming call" listener subscribes to INSERTs on
-- sessions, which requires the table to be in the realtime publication.
-- (Presence uses broadcast and needs no publication.)
-- ===========================================================================
do $$
begin
  alter publication supabase_realtime add table public.sessions;
exception
  when duplicate_object then null;  -- already added, ignore
end $$;
