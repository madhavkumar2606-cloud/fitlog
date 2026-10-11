-- FitLog access approval. Run this once in Supabase: SQL Editor -> New query -> Run.
-- Safe to run more than once.

-- ---------- Admins (only you). Nobody can add themselves from the app. ----------
create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);

create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

-- ---------- Payment settings shown on the request screen ----------
create table if not exists public.app_config (
  id          int primary key default 1 check (id = 1),
  upi_id      text not null default '',
  payee_name  text not null default 'FitLog',
  amount      numeric,
  price_text  text not null default '',
  message     text not null default 'Pay using the QR or UPI ID, then send your request. Got a free invite? Just tap Request access.'
);
insert into public.app_config (id) values (1) on conflict (id) do nothing;

-- ---------- One access request per person ----------
create table if not exists public.access_requests (
  user_id       uuid primary key references public.profiles(id) on delete cascade,
  utr           text,
  note          text,
  status        text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  access_until  timestamptz,           -- null + approved = access forever
  admin_note    text,
  requested_at  timestamptz not null default now(),
  decided_at    timestamptz
);

alter table public.admins          enable row level security;
alter table public.app_config      enable row level security;
alter table public.access_requests enable row level security;

drop policy if exists "admins read self"  on public.admins;
create policy "admins read self" on public.admins for select to authenticated using (user_id = auth.uid());

drop policy if exists "config read"  on public.app_config;
drop policy if exists "config admin" on public.app_config;
create policy "config read"  on public.app_config for select to authenticated using (true);
create policy "config admin" on public.app_config for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists "requests read"         on public.access_requests;
drop policy if exists "requests create"       on public.access_requests;
drop policy if exists "requests resubmit"     on public.access_requests;
drop policy if exists "requests admin decide" on public.access_requests;

-- You see your own request; admins see everyone's.
create policy "requests read" on public.access_requests for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

-- People can only create a *pending* request for themselves.
create policy "requests create" on public.access_requests for insert to authenticated
  with check (user_id = auth.uid() and status = 'pending' and access_until is null and decided_at is null);

-- People can re-send a request (after rejection or expiry), but can never approve themselves.
create policy "requests resubmit" on public.access_requests for update to authenticated
  using (user_id = auth.uid() and (status <> 'approved' or access_until < now()))
  with check (user_id = auth.uid() and status = 'pending' and access_until is null and decided_at is null);

-- Only admins approve, reject, extend or revoke.
create policy "requests admin decide" on public.access_requests for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---------- Make YOURSELF the admin ----------
-- Replace the email below with the email you signed up with in FitLog, then run this line.
-- insert into public.admins (user_id) select id from auth.users where email = 'your-email@gmail.com' on conflict do nothing;
