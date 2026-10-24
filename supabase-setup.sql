-- CIT Student Government Transaction Site: database setup for Supabase
-- Run this ONCE in Supabase: SQL Editor > New query > paste everything > Run.
--
-- BEFORE running: change 'CHANGE-ME-CODE' below to your own secret access code.
-- People must type this code when they sign up. Anyone who signs up without it
-- gets an account but sees no data until an admin approves them.

-- ---------- tables ----------

create table if not exists public.members (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  role       text not null default 'officer' check (role in ('officer', 'admin')),
  created_at timestamptz not null default now()
);

create table if not exists public.config (
  key   text primary key,
  value text not null
);

insert into public.config (key, value)
values ('signup_code', 'CHANGE-ME-CODE')
on conflict (key) do nothing;

create table if not exists public.transactions (
  id         bigint generated always as identity primary key,
  ref        text not null unique,
  created_at timestamptz not null default now(),
  name       text not null check (char_length(name) between 3 and 80),
  course     text not null check (char_length(course) between 1 and 60),
  year       text not null check (char_length(year) between 1 and 40),
  type       text not null check (char_length(type) between 1 and 60),
  amount     numeric(12, 2) not null check (amount >= 1 and amount <= 100000),
  created_by uuid not null default auth.uid() references auth.users (id)
);

create index if not exists transactions_created_at_idx on public.transactions (created_at);

create table if not exists public.options (
  key   text primary key check (key in ('courses', 'years', 'types')),
  items jsonb not null
);

-- ---------- helper functions ----------

create or replace function public.is_member()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (select 1 from public.members where user_id = auth.uid());
$$;

create or replace function public.is_admin()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (select 1 from public.members where user_id = auth.uid() and role = 'admin');
$$;

-- When someone signs up with the right access code, they become an officer automatically.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1 from public.config
    where key = 'signup_code'
      and value = coalesce(new.raw_user_meta_data ->> 'access_code', '')
  ) then
    insert into public.members (user_id, role) values (new.id, 'officer')
    on conflict (user_id) do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- security rules (Row Level Security) ----------

alter table public.members      enable row level security;
alter table public.config       enable row level security;   -- no policies: nobody can read it through the API
alter table public.transactions enable row level security;
alter table public.options      enable row level security;

drop policy if exists "read own membership" on public.members;
create policy "read own membership" on public.members
  for select to authenticated using (user_id = auth.uid());

drop policy if exists "members read transactions" on public.transactions;
create policy "members read transactions" on public.transactions
  for select to authenticated using (public.is_member());

drop policy if exists "members add transactions" on public.transactions;
create policy "members add transactions" on public.transactions
  for insert to authenticated with check (public.is_member() and created_by = auth.uid());

drop policy if exists "admins delete transactions" on public.transactions;
create policy "admins delete transactions" on public.transactions
  for delete to authenticated using (public.is_admin());

drop policy if exists "members read options" on public.options;
create policy "members read options" on public.options
  for select to authenticated using (public.is_member());

drop policy if exists "admins add options" on public.options;
create policy "admins add options" on public.options
  for insert to authenticated with check (public.is_admin());

drop policy if exists "admins change options" on public.options;
create policy "admins change options" on public.options
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "admins delete options" on public.options;
create policy "admins delete options" on public.options
  for delete to authenticated using (public.is_admin());

-- ---------- AFTER you have signed up on the website ----------
-- Make yourself an admin (replace the email with the one you signed up with),
-- run this as a separate query:
--
--   insert into public.members (user_id, role)
--   select id, 'admin' from auth.users where email = 'you@example.com'
--   on conflict (user_id) do update set role = 'admin';
--
-- To approve someone who signed up without the code:
--
--   insert into public.members (user_id, role)
--   select id, 'officer' from auth.users where email = 'officer@example.com'
--   on conflict (user_id) do nothing;
--
-- To change the access code later:
--
--   update public.config set value = 'NEW-CODE' where key = 'signup_code';
