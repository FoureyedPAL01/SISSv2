-- =====================================================================
-- SISS Supabase schema (clean, canonical version)
-- ---------------------------------------------------------------------
-- This file is the SINGLE source of truth for your SISS database
-- structure. Run it on:
--   - A fresh project, OR
--   - An existing project AFTER you've applied the migrations in
--     supabase_migrations_cleanup.sql (see that file for details).
--
-- Sections:
--   0. Safety & extensions
--   1. Core tables: users, devices
--   2. Domain tables: crop_profiles, sensor_readings, pump_logs,
--                     irrigation_schedules, system_alerts
--   3. RLS policies
--   4. Trigger functions & triggers
--   5. Realtime publication & cron cleanup job
--   6. Seed data
--
-- NOTE:
-- - Identifiers are in snake_case for Postgres ergonomics.
-- - App code (Flutter/Python) can continue to use camelCase fields
--   that map directly to these columns.
-- =====================================================================


-- =====================================================================
-- 0. Safety & extensions
-- =====================================================================

-- Enable pgcrypto for gen_random_uuid (usually already enabled on Supabase)
create extension if not exists pgcrypto;

-- Enable pg_cron for scheduled jobs (if allowed in your Supabase project)
create extension if not exists pg_cron;


-- =====================================================================
-- 1. Core tables: users, devices
-- =====================================================================

-- Users table linked to Supabase auth.users
create table if not exists public.users (
  id         uuid primary key references auth.users(id) on delete cascade,
  full_name  text,
  email      text unique not null,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);


-- Devices owned by a user
create table if not exists public.devices (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.users(id) on delete cascade,
  name            text not null,
  location        text,
  crop_profile_id bigint, -- FK to crop_profiles, added after crop_profiles exists
  created_at      timestamptz default now(),
  updated_at      timestamptz default now(),
  last_seen       timestamptz
);


-- =====================================================================
-- 2. Domain tables
-- =====================================================================

-- 2.1 Crop profiles (per-user, referenced by devices)
create table if not exists public.crop_profiles (
  id                        bigserial primary key,
  user_id                   uuid not null references public.users(id) on delete cascade,
  name                      text not null,
  min_moisture              numeric not null,
  max_moisture              numeric not null,
  weather_sensitivity       text default 'medium'
    check (weather_sensitivity in ('low', 'medium', 'high')),
  irrigation_duration_minutes integer default 10,
  notes                     text,
  created_at                timestamptz default now(),
  updated_at                timestamptz default now()
);

-- Now link devices.crop_profile_id to crop_profiles
alter table public.devices
  add constraint devices_crop_profile_fk
  foreign key (crop_profile_id) references public.crop_profiles(id)
  on delete set null;


-- 2.2 Sensor readings
create table if not exists public.sensor_readings (
  id            bigserial primary key,
  device_id     uuid not null references public.devices(id) on delete cascade,
  soil_moisture numeric,       -- percentage 0–100
  temperature_c numeric,       -- °C
  humidity      numeric,       -- % relative humidity
  rain_detected boolean default false,
  flow_litres   numeric,       -- litres per unit time (see docs)
  recorded_at   timestamptz default now()
);


-- 2.3 Pump logs
create table if not exists public.pump_logs (
  id                bigserial primary key,
  device_id         uuid not null references public.devices(id) on delete cascade,
  triggered_by      text not null
    check (triggered_by in ('auto', 'manual', 'schedule')),
  action            text
    check (action in ('ON', 'OFF')),
  source            text, -- e.g. 'app', 'backend', 'schedule'
  pump_on_at        timestamptz not null,
  pump_off_at       timestamptz,
  duration_seconds  integer,
  water_used_litres numeric,
  reason            text,
  created_at        timestamptz default now()
);


-- 2.4 Irrigation schedules
create table if not exists public.irrigation_schedules (
  id                uuid primary key default gen_random_uuid(),
  device_id         uuid not null references public.devices(id) on delete cascade,
  schedule_time     time not null,
  repeat_days       integer[]
    check (repeat_days <@ array[0,1,2,3,4,5,6]),
  duration_minutes  integer default 10,
  is_active         boolean default true,
  created_at        timestamptz default now()
);


-- 2.5 System alerts
create table if not exists public.system_alerts (
  id          bigserial primary key,
  device_id   uuid references public.devices(id) on delete cascade,
  -- null device_id = system-wide alert (not device-specific)
  alert_type  text not null,
  message     text not null,
  severity    text default 'warning'
    check (severity in ('info', 'warning', 'critical')),
  status      text default 'active'
    check (status in ('active', 'resolved')),
  resolved_at timestamptz,
  created_at  timestamptz default now()
);


-- =====================================================================
-- 3. Row Level Security (RLS) policies
-- =====================================================================

-- Enable RLS
alter table public.users               enable row level security;
alter table public.devices             enable row level security;
alter table public.crop_profiles       enable row level security;
alter table public.sensor_readings     enable row level security;
alter table public.pump_logs           enable row level security;
alter table public.irrigation_schedules enable row level security;
alter table public.system_alerts       enable row level security;


-- 3.1 users: a user can only see and edit their own row
drop policy if exists "users: can read own"   on public.users;
drop policy if exists "users: can update own" on public.users;
drop policy if exists "users: can insert own" on public.users;

create policy "users: can read own"
  on public.users for select
  using (id = auth.uid());

create policy "users: can update own"
  on public.users for update
  using (id = auth.uid())
  with check (id = auth.uid());

create policy "users: can insert own"
  on public.users for insert
  with check (id = auth.uid());


-- 3.2 devices: fully owned by the user
drop policy if exists "devices: owner only" on public.devices;

create policy "devices: owner only"
  on public.devices for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());


-- 3.3 crop_profiles: per-user
drop policy if exists "crop_profiles: read for all authenticated" on public.crop_profiles;
drop policy if exists "crop_profiles: user owned" on public.crop_profiles;

create policy "crop_profiles: user owned"
  on public.crop_profiles for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());


-- 3.4 sensor_readings: only readings from own devices
drop policy if exists "sensor_readings: device owner only" on public.sensor_readings;

create policy "sensor_readings: device owner only"
  on public.sensor_readings for all
  using (
    device_id in (
      select id from public.devices where user_id = auth.uid()
    )
  )
  with check (
    device_id in (
      select id from public.devices where user_id = auth.uid()
    )
  );


-- 3.5 pump_logs: only logs from own devices
drop policy if exists "pump_logs: device owner only" on public.pump_logs;

create policy "pump_logs: device owner only"
  on public.pump_logs for all
  using (
    device_id in (
      select id from public.devices where user_id = auth.uid()
    )
  )
  with check (
    device_id in (
      select id from public.devices where user_id = auth.uid()
    )
  );


-- 3.6 irrigation_schedules: only schedules for own devices
drop policy if exists "schedules: device owner only" on public.irrigation_schedules;

create policy "schedules: device owner only"
  on public.irrigation_schedules for all
  using (
    device_id in (
      select id from public.devices where user_id = auth.uid()
    )
  )
  with check (
    device_id in (
      select id from public.devices where user_id = auth.uid()
    )
  );


-- 3.7 system_alerts: device owner or system-wide
drop policy if exists "alerts: device owner or system-wide" on public.system_alerts;

create policy "alerts: device owner or system-wide"
  on public.system_alerts for select
  using (
    device_id is null
    or device_id in (
      select id from public.devices where user_id = auth.uid()
    )
  );


-- =====================================================================
-- 4. Trigger functions & triggers
-- =====================================================================

-- 4.1 Generic updated_at trigger
create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at := now();
  return new;
end;
$$ language plpgsql;


-- Attach to users, devices, crop_profiles
drop trigger if exists trg_users_updated_at   on public.users;
drop trigger if exists trg_devices_updated_at on public.devices;
drop trigger if exists trg_crop_profiles_updated_at on public.crop_profiles;

create trigger trg_users_updated_at
  before update on public.users
  for each row execute procedure public.set_updated_at();

create trigger trg_devices_updated_at
  before update on public.devices
  for each row execute procedure public.set_updated_at();

create trigger trg_crop_profiles_updated_at
  before update on public.crop_profiles
  for each row execute procedure public.set_updated_at();


-- 4.2 handle_new_user: sync auth.users → public.users and devices
create or replace function public.handle_new_user()
returns trigger as $$
begin
  -- Insert user record if missing
  insert into public.users (id, email)
  values (new.id, new.email)
  on conflict (id) do nothing;

  -- Auto-create default device for the new user
  insert into public.devices (user_id, name, location)
  values (new.id, 'My Garden', 'Not Set')
  on conflict do nothing;

  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- 4.3 compute_pump_log_totals: duration & water_used
create or replace function public.compute_pump_log_totals()
returns trigger as $$
begin
  -- Only compute when pump_off_at is being set for the first time
  if new.pump_off_at is not null and old.pump_off_at is null then
    new.duration_seconds :=
      extract(epoch from (new.pump_off_at - new.pump_on_at))::integer;

    -- Fallback estimation if no explicit water_used_litres provided
    if new.water_used_litres is null then
      -- Example: assume 1.5 L/min
      new.water_used_litres :=
        round((new.duration_seconds / 60.0 * 1.5)::numeric, 3);
    end if;
  end if;

  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_compute_pump_log_totals on public.pump_logs;

create trigger trg_compute_pump_log_totals
  before update on public.pump_logs
  for each row execute procedure public.compute_pump_log_totals();


-- =====================================================================
-- 5. Realtime publication & cron cleanup job
-- =====================================================================

-- Realtime publication: add key tables
-- (supabase_realtime is created by Supabase; these ALTERs may fail
--  if the table is already present, which is safe.)
do $$
begin
  begin
    alter publication supabase_realtime add table
      public.sensor_readings,
      public.pump_logs,
      public.system_alerts;
  exception
    when others then
      null;
  end;
end;
$$;


-- Cron: delete old sensor_readings (older than 90 days)
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if not exists (
      select 1 from cron.job where jobname = 'delete-old-sensor-readings'
    ) then
      perform cron.schedule(
        'delete-old-sensor-readings',
        '0 2 * * *',
        $sql$
          delete from public.sensor_readings
          where recorded_at < now() - interval '90 days';
        $sql$
      );
    end if;
  end if;
end;
$$;


-- =====================================================================
-- 6. Seed data
-- =====================================================================

-- Global-style defaults for convenience.
-- These are OPTIONAL; they assume per-user crop profiles and will be
-- cloned or adapted by the app/backend as needed.
insert into public.crop_profiles (
  user_id, name, min_moisture, max_moisture,
  weather_sensitivity, irrigation_duration_minutes
)
select
  u.id,
  v.name,
  v.min_moisture,
  v.max_moisture,
  v.weather_sensitivity,
  v.irrigation_duration_minutes
from public.users u
cross join (
  values
    ('General', 30::numeric, 70::numeric, 'medium', 10),
    ('Wheat',   40::numeric, 65::numeric, 'medium', 12),
    ('Rice',    60::numeric, 85::numeric, 'high',   20),
    ('Tomato',  50::numeric, 75::numeric, 'high',   15)
) as v(name, min_moisture, max_moisture, weather_sensitivity, irrigation_duration_minutes)
on conflict do nothing;

