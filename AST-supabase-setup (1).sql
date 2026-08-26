-- ============================================================
--  AST — Alpin Samverkansträning
--  Supabase SQL Setup
--  Kör detta i Supabase → SQL Editor → New query
-- ============================================================

-- 1. EXTENSIONS
create extension if not exists "uuid-ossp";

-- 2. PROFILES (linked to Supabase Auth users)
create table public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  fname       text not null,
  lname       text not null,
  club        text not null,
  role        text not null default 'user' check (role in ('admin','user')),
  created_at  timestamptz default now()
);
alter table public.profiles enable row level security;
-- Everyone can read profiles (for showing creator names)
create policy "profiles_read_all"   on public.profiles for select using (true);
-- Users can update their own profile
create policy "profiles_update_own" on public.profiles for update using (auth.uid() = id);
-- Admins can update any profile (for role management)
create policy "profiles_admin_update" on public.profiles for update
  using (exists (select 1 from public.profiles where id = auth.uid() and role = 'admin'));

-- 3. EVENTS
create table public.events (
  id          uuid primary key default uuid_generate_v4(),
  created_by  uuid references public.profiles(id),
  groups      text[] not null default '{}',
  from_date   date not null,
  to_date     date not null,
  venue       text,
  organizer   text,
  email       text,
  phone       text,
  whatsapp    text,
  info        text,
  created_at  timestamptz default now()
);
alter table public.events enable row level security;
-- Anyone logged in can read events
create policy "events_read_all"   on public.events for select using (auth.role() = 'authenticated');
-- Anyone logged in can insert events
create policy "events_insert"     on public.events for insert with check (auth.role() = 'authenticated');
-- Only creator or admin can update/delete
create policy "events_update_own" on public.events for update
  using (created_by = auth.uid() or exists (
    select 1 from public.profiles where id = auth.uid() and role = 'admin'
  ));
create policy "events_delete_own" on public.events for delete
  using (created_by = auth.uid() or exists (
    select 1 from public.profiles where id = auth.uid() and role = 'admin'
  ));

-- 4. REGISTRATIONS
create table public.registrations (
  id               uuid primary key default uuid_generate_v4(),
  event_id         uuid references public.events(id) on delete cascade,
  created_by       uuid references public.profiles(id),
  fname            text not null,
  lname            text not null,
  club             text not null,
  age_group        text not null,
  guardian_fname   text not null,
  guardian_lname   text not null,
  guardian_phone   text not null,
  created_at       timestamptz default now()
);
alter table public.registrations enable row level security;
-- Anyone logged in can read registrations
create policy "regs_read_all"   on public.registrations for select using (auth.role() = 'authenticated');
-- Anyone logged in can insert
create policy "regs_insert"     on public.registrations for insert with check (auth.role() = 'authenticated');
-- Admin or event creator can delete
create policy "regs_delete"     on public.registrations for delete
  using (
    created_by = auth.uid()
    or exists (select 1 from public.profiles where id = auth.uid() and role = 'admin')
    or exists (select 1 from public.events e where e.id = event_id and e.created_by = auth.uid())
  );

-- 5. AUTO-CREATE PROFILE ON SIGNUP (Edge Function alternative)
-- This trigger creates a profile row when a new auth user signs up.
-- The fname/lname/club come from raw_user_meta_data set during signUp().
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
declare
  user_count int;
  new_role text;
begin
  select count(*) into user_count from public.profiles;
  -- First user ever becomes admin automatically
  if user_count = 0 then
    new_role := 'admin';
  else
    new_role := 'user';
  end if;
  insert into public.profiles (id, fname, lname, club, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'fname', ''),
    coalesce(new.raw_user_meta_data->>'lname', ''),
    coalesce(new.raw_user_meta_data->>'club', ''),
    new_role
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- 6. ADMIN UPGRADE FUNCTION (call from app with admin secret)
-- Allows promoting a user to admin by email
create or replace function public.set_admin_by_email(target_email text, admin_code text)
returns text language plpgsql security definer as $$
begin
  if admin_code <> 'AST2025' then
    return 'Fel adminkod';
  end if;
  update public.profiles
  set role = 'admin'
  where id = (select id from auth.users where email = target_email);
  if found then return 'OK'; else return 'Användare hittades inte'; end if;
end;
$$;

-- 7. USEFUL VIEWS
create or replace view public.registrations_with_event as
  select
    r.*,
    e.venue, e.organizer, e.from_date, e.to_date, e.groups as event_groups,
    p.fname as creator_fname, p.lname as creator_lname, p.club as creator_club
  from public.registrations r
  join public.events e on e.id = r.event_id
  left join public.profiles p on p.id = r.created_by;

-- ============================================================
--  DONE! Nu är databasen klar.
--  Nästa steg: Kör AST-supabase-app.html lokalt och testa.
-- ============================================================

-- ============================================================
--  TILLÄGG: Åkarregister (saved_skiers)
--  Kör detta i Supabase → SQL Editor
-- ============================================================

create table public.saved_skiers (
  id           uuid primary key default uuid_generate_v4(),
  owner_id     uuid references public.profiles(id) on delete cascade,
  fname        text not null,
  lname        text not null,
  birth_year   int  not null,
  age_group    text not null,
  club         text not null,
  guardian_fname  text not null,
  guardian_lname  text not null,
  guardian_phone  text not null,
  created_at   timestamptz default now(),
  updated_at   timestamptz default now()
);

alter table public.saved_skiers enable row level security;

-- Bara ägaren ser sina egna åkare (GDPR: ingen annan har åtkomst)
create policy "skiers_owner_only" on public.saved_skiers
  for all using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

-- Trigger: uppdatera updated_at automatiskt
create or replace function update_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;

create trigger saved_skiers_updated_at
  before update on public.saved_skiers
  for each row execute procedure update_updated_at();

-- ============================================================
--  GDPR: Kommentar om dataskydd
--  Personuppgifter i saved_skiers tillhör inloggad användare.
--  Raderas automatiskt om användarkontot tas bort (cascade).
-- ============================================================

-- ============================================================
--  SÄKERHET: Adminkod server-side + radera konto
--  Kör detta i Supabase → SQL Editor
-- ============================================================

-- 1. Spara adminkoden säkert i databasen (ändra 'AST2025' till din kod)
create table if not exists public.app_secrets (
  key   text primary key,
  value text not null
);
-- Kör detta separat med din valda adminkod:
-- insert into public.app_secrets (key, value) values ('admin_code', 'DIN_ADMINKOD_HÄR');
-- update public.app_secrets set value = 'DIN_ADMINKOD_HÄR' where key = 'admin_code';

alter table public.app_secrets enable row level security;
-- Ingen publik läsåtkomst — bara via RPC
create policy "no_direct_access" on public.app_secrets for select using (false);

-- 2. RPC: Kontrollera adminkod (returnerar true/false, avslöjar aldrig koden)
create or replace function public.check_admin_code(input_code text)
returns boolean language plpgsql security definer as $$
declare stored_code text;
begin
  select value into stored_code from public.app_secrets where key = 'admin_code';
  return stored_code is not null and input_code = stored_code;
end;
$$;

-- 3. RPC: Radera eget konto (GDPR artikel 17)
create or replace function public.delete_own_account()
returns void language plpgsql security definer as $$
begin
  delete from auth.users where id = auth.uid();
end;
$$;

-- ============================================================
--  RATE LIMITING (aktivera i Supabase Dashboard)
--  Authentication → Settings → Rate limits:
--  - Email signups: 5/timme per IP
--  - Password logins: 10/timme per IP
-- ============================================================
