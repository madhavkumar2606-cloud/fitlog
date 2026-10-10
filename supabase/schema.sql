-- FitLog backend schema.
-- Paste this whole file into Supabase: SQL Editor -> New query -> Run.
-- Safe to run more than once.

-- ---------- Public profiles ----------
create table if not exists public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  username      text not null unique check (username ~ '^[a-z0-9_]{3,20}$'),
  display_name  text not null check (char_length(display_name) between 1 and 40),
  avatar_color  int  not null default 0,
  total_xp      int  not null default 0,
  level         int  not null default 1,
  streak        int  not null default 0,
  updated_at    timestamptz not null default now()
);

-- ---------- Friendships ----------
create table if not exists public.friendships (
  id          bigint generated always as identity primary key,
  requester   uuid not null references public.profiles(id) on delete cascade,
  addressee   uuid not null references public.profiles(id) on delete cascade,
  status      text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at  timestamptz not null default now(),
  check (requester <> addressee)
);
-- Only one friendship row per pair of people, whichever direction it was sent.
create unique index if not exists friendships_pair
  on public.friendships (least(requester, addressee), greatest(requester, addressee));

-- ---------- Weekly XP (leaderboard) ----------
create table if not exists public.weekly_xp (
  user_id     uuid not null references public.profiles(id) on delete cascade,
  week_start  date not null,
  xp          int  not null default 0,
  workouts    int  not null default 0,
  updated_at  timestamptz not null default now(),
  primary key (user_id, week_start)
);

-- ---------- Badges ----------
create table if not exists public.user_badges (
  user_id    uuid not null references public.profiles(id) on delete cascade,
  badge      text not null,
  earned_at  timestamptz not null default now(),
  primary key (user_id, badge)
);

-- ---------- Helper: are two people friends? ----------
create or replace function public.is_friend(a uuid, b uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.friendships f
    where f.status = 'accepted'
      and ((f.requester = a and f.addressee = b) or (f.requester = b and f.addressee = a))
  );
$$;

-- ---------- Row level security ----------
alter table public.profiles    enable row level security;
alter table public.friendships enable row level security;
alter table public.weekly_xp   enable row level security;
alter table public.user_badges enable row level security;

-- Profiles: any signed-in user can see names/levels (needed to search by username).
drop policy if exists "profiles read"   on public.profiles;
drop policy if exists "profiles insert" on public.profiles;
drop policy if exists "profiles update" on public.profiles;
create policy "profiles read"   on public.profiles for select to authenticated using (true);
create policy "profiles insert" on public.profiles for insert to authenticated with check (id = auth.uid());
create policy "profiles update" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- Friendships: you see and delete your own; you send as yourself; only the receiver accepts.
drop policy if exists "friendships read"   on public.friendships;
drop policy if exists "friendships send"   on public.friendships;
drop policy if exists "friendships accept" on public.friendships;
drop policy if exists "friendships remove" on public.friendships;
create policy "friendships read"   on public.friendships for select to authenticated
  using (auth.uid() in (requester, addressee));
create policy "friendships send"   on public.friendships for insert to authenticated
  with check (requester = auth.uid() and status = 'pending');
create policy "friendships accept" on public.friendships for update to authenticated
  using (addressee = auth.uid()) with check (addressee = auth.uid() and status = 'accepted');
create policy "friendships remove" on public.friendships for delete to authenticated
  using (auth.uid() in (requester, addressee));

-- Weekly XP and badges: you write your own; you and your friends can read them.
drop policy if exists "weekly read"  on public.weekly_xp;
drop policy if exists "weekly write" on public.weekly_xp;
drop policy if exists "weekly edit"  on public.weekly_xp;
create policy "weekly read"  on public.weekly_xp for select to authenticated
  using (user_id = auth.uid() or public.is_friend(auth.uid(), user_id));
create policy "weekly write" on public.weekly_xp for insert to authenticated with check (user_id = auth.uid());
create policy "weekly edit"  on public.weekly_xp for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "badges read"  on public.user_badges;
drop policy if exists "badges write" on public.user_badges;
drop policy if exists "badges edit"  on public.user_badges;
create policy "badges read"  on public.user_badges for select to authenticated
  using (user_id = auth.uid() or public.is_friend(auth.uid(), user_id));
create policy "badges write" on public.user_badges for insert to authenticated with check (user_id = auth.uid());
create policy "badges edit"  on public.user_badges for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
