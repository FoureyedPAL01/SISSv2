//q1
create table public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  -- ↑ links to Supabase's built-in auth table; deleting auth user cascades here
  full_name text,
  email text unique not null,
  created_at timestamptz default now()
);

//q2
create table public.devices (
  id uuid primary key default gen_random_uuid(),
  -- gen_random_uuid() auto-generates a unique ID
  user_id uuid not null references public.users(id) on delete cascade,
  name text not null,                    -- e.g. "Garden Plot A"
  location text,
  crop_profile text default 'General',  -- Wheat, Rice, Tomato, etc.
  moisture_threshold_low integer default 30,   -- % below → pump ON
  moisture_threshold_high integer default 70,  -- % above → pump OFF
  created_at timestamptz default now()
);

//q3
create table public.sensor_readings (
  id bigserial primary key,
  -- bigserial = auto-incrementing big integer, good for high-frequency inserts
  device_id uuid not null references public.devices(id) on delete cascade,
  soil_moisture integer,     -- percentage 0–100
  temperature numeric(5,2),  -- °C, e.g. 28.50
  humidity numeric(5,2),     -- % relative humidity
  rain_detected boolean default false,
  flow_rate numeric(7,3),    -- litres per minute
  recorded_at timestamptz default now()
);

//q4
create table public.pump_logs (
  id bigserial primary key,
  device_id uuid not null references public.devices(id) on delete cascade,
  triggered_by text check (triggered_by in ('auto', 'manual', 'schedule')),
  -- check() enforces only these three string values are allowed
  pump_on_at timestamptz not null,
  pump_off_at timestamptz,        -- null means pump is currently running
  duration_seconds integer,       -- calculated when pump turns off
  water_used_litres numeric(8,3), -- estimated from flow sensor
  reason text                     -- e.g. "soil dry", "manual override"
);

//q5
create table public.crop_profiles (
  id serial primary key,
  crop_name text unique not null,           -- "Wheat", "Rice", "Tomato"
  moisture_min integer not null,            -- ideal moisture lower bound
  moisture_max integer not null,
  weather_sensitivity text default 'medium' -- low / medium / high
    check (weather_sensitivity in ('low', 'medium', 'high')),
  irrigation_duration_minutes integer default 10,
  notes text
);

-- Seed with default crops right away
insert into public.crop_profiles
  (crop_name, moisture_min, moisture_max, weather_sensitivity, irrigation_duration_minutes)
values
  ('General', 30, 70, 'medium', 10),
  ('Wheat',   40, 65, 'medium', 12),
  ('Rice',    60, 85, 'high',   20),
  ('Tomato',  50, 75, 'high',   15);

//q6
create table public.irrigation_schedules (
  id uuid primary key default gen_random_uuid(),
  device_id uuid not null references public.devices(id) on delete cascade,
  schedule_time time not null,      -- e.g. '06:00:00'
  repeat_days integer[] check (
  repeat_days <@ array[0,1,2,3,4,5,6]
  ),            -- e.g. ARRAY['Mon','Wed','Fri']
  -- text[] is a PostgreSQL array of strings
  duration_minutes integer default 10,
  is_active boolean default true,
  created_at timestamptz default now()
);

//q7
-- Enable RLS on every table
alter table public.users enable row level security;
alter table public.devices enable row level security;
alter table public.sensor_readings enable row level security;
alter table public.pump_logs enable row level security;
alter table public.crop_profiles enable row level security;
alter table public.irrigation_schedules enable row level security;

-- ─── users ───────────────────────────────────────────────────
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

-- ─── devices ─────────────────────────────────────────────────
create policy "devices: owner only"
  on public.devices for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ─── sensor_readings ─────────────────────────────────────────
-- A user can read readings only from their own devices
create policy "sensor_readings: device owner only"
  on public.sensor_readings for all
  using (
    device_id in (select id from public.devices where user_id = auth.uid())
  )
  with check (
    device_id in (select id from public.devices where user_id = auth.uid())
  );


-- ─── pump_logs ───────────────────────────────────────────────
create policy "pump_logs: device owner only"
  on public.pump_logs for all
  using (
    device_id in (select id from public.devices where user_id = auth.uid())
  )
  with check (
    device_id in (select id from public.devices where user_id = auth.uid())
  );

-- ─── crop_profiles ───────────────────────────────────────────
-- Crop profiles are global/read-only for all authenticated users
create policy "crop_profiles: read for all authenticated"
  on public.crop_profiles for select
  using (auth.role() = 'authenticated');
  -- auth.role() returns 'authenticated' for logged-in users, 'anon' for guests

-- ─── irrigation_schedules ────────────────────────────────────
create policy "schedules: device owner only"
  on public.irrigation_schedules for all
  using (
    device_id in (select id from public.devices where user_id = auth.uid())
  )
  with check (
    device_id in (select id from public.devices where user_id = auth.uid())
  );

//q8
-- Enable the pg_cron extension (run once)
create extension if not exists pg_cron;

-- Schedule a daily cleanup job at 2:00 AM UTC
-- retaining only the last 90 days of readings
select cron.schedule(
  'delete-old-sensor-readings',     -- job name
  '0 2 * * *',                      -- cron expression: daily at 02:00 UTC
  $$
    delete from public.sensor_readings
    where recorded_at < now() - interval '90 days';
  $$
);

//q9
create or replace function compute_pump_log_totals()
returns trigger as $$
begin
  -- Only compute when pump_off_at is being set for the first time
  if new.pump_off_at is not null and old.pump_off_at is null then

    new.duration_seconds := extract(epoch from (new.pump_off_at - new.pump_on_at))::integer;
    -- extract(epoch from interval) converts a time difference to total seconds

    -- Fallback: if flow sensor data isn't available, estimate from duration
    -- YF-S201 typical flow rate: ~1.5 L/min for a 12V mini submersible
    if new.water_used_litres is null then
      new.water_used_litres := round((new.duration_seconds / 60.0 * 1.5)::numeric, 3);
    end if;
    -- The backend should ideally pass the real flow sensor value;
    -- this is a safety fallback only

  end if;
  return new;
end;
$$ language plpgsql;

-- Attach to pump_logs, fires before the UPDATE is committed
create trigger trg_compute_pump_log_totals
  before update on public.pump_logs
  for each row execute procedure compute_pump_log_totals();

//q10
-- Add tables to Supabase's internal realtime publication
alter publication supabase_realtime add table public.sensor_readings;
alter publication supabase_realtime add table public.pump_logs;
-- supabase_realtime is a PostgreSQL publication Supabase creates by default

//q11
-- Speed up time-range queries on sensor_readings
create index idx_sensor_readings_device_time
  on public.sensor_readings (device_id, recorded_at desc);
-- desc = newest first, which is how dashboards typically query

-- Speed up pump log lookups per device
create index idx_pump_logs_device
  on public.pump_logs (device_id, pump_on_at desc);

//q12
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  -- Insert user record
  INSERT INTO public.users (id, email)
  VALUES (NEW.id, NEW.email);
  
  -- Auto-create default device for the new user
  -- User can rename it later in the Flutter app
  INSERT INTO public.devices (user_id, name, location, crop_profile)
  VALUES (NEW.id, 'My Garden', 'Not Set', 'General');
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

//q13
-- Reusable function that sets updated_at to now() on any update
create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at := now();
  return new;
end;
$$ language plpgsql;

-- Add column and attach trigger to devices
alter table public.devices
  add column updated_at timestamptz default now();

create trigger trg_devices_updated_at
  before update on public.devices
  for each row execute procedure public.set_updated_at();

-- Add column and attach trigger to users
alter table public.users
  add column updated_at timestamptz default now();

create trigger trg_users_updated_at
  before update on public.users
  for each row execute procedure public.set_updated_at();

//q14
create table public.system_alerts (
  id          bigserial primary key,
  device_id   uuid references public.devices(id) on delete cascade,
  -- null device_id = system-wide alert (not device-specific)
  alert_type  text not null,
  -- e.g. 'low_moisture', 'pump_fault', 'sensor_offline', 'high_temp'
  message     text not null,
  severity    text default 'warning'
    check (severity in ('info', 'warning', 'critical')),
  status      text default 'active'
    check (status in ('active', 'resolved')),
  resolved_at timestamptz,
  created_at  timestamptz default now()
);

//q15
alter table public.system_alerts enable row level security;

//q16
create policy "alerts: device owner or system-wide"
  on public.system_alerts for select
  using (
    device_id is null
    or device_id in (
      select id from public.devices where user_id = auth.uid()
    )
  );

//q17
alter publication supabase_realtime add table public.system_alerts;

//q18
create index idx_system_alerts_device_time
  on public.system_alerts (device_id, created_at desc);

//q19
-- First get a device_id from your devices table to test with
-- or use null for a system-wide alert
insert into public.system_alerts (device_id, alert_type, message, severity, status)
values (null, 'system_check', 'System initialized successfully.', 'info', 'resolved');

//q20
-- Option A: Add missing columns to match what ESP32/backend sends
ALTER TABLE public.sensor_readings 
  ADD COLUMN IF NOT EXISTS temperature_c numeric(5,2),
  ADD COLUMN IF NOT EXISTS flow_litres numeric(7,3);

//q21
INSERT INTO public.devices (user_id, name, location, crop_profile)
VALUES ('9c059af9-97bf-466f-9ef1-6d42b5aff96e', 'Garden 1', 'Backyard', 'General')
RETURNING id;

//q22
   SELECT * FROM public.devices;
   
//q23
-- Add missing columns that ESP32/backend sends
ALTER TABLE public.sensor_readings 
  ADD COLUMN IF NOT EXISTS temperature_c numeric(5,2),
  ADD COLUMN IF NOT EXISTS flow_litres numeric(7,3);

//q24
   SELECT id, name FROM public.devices;
   
//q25
-- Check if device with the ID from config.h exists
SELECT id, name, user_id FROM public.devices 
WHERE id = 'bb6426cb-da78-4e06-81d9-add1a491e3cd';

//q26
-- Fix 1: Change soil_moisture from integer to numeric
ALTER TABLE public.sensor_readings 
ALTER COLUMN soil_moisture TYPE numeric(5,2);

-- Fix 2: Add missing columns for temperature/humidity/flow
ALTER TABLE public.sensor_readings 
  ADD COLUMN IF NOT EXISTS temperature_c numeric(5,2),
  ADD COLUMN IF NOT EXISTS flow_litres numeric(7,3);

-- Fix 3: Add last_seen column to devices (for fault detector)
ALTER TABLE public.devices 
  ADD COLUMN IF NOT EXISTS last_seen timestamptz;

-- Fix 4: Enable realtime on sensor_readings
ALTER PUBLICATION supabase_realtime ADD TABLE public.sensor_readings;

//q27
-- Fix 1: Change soil_moisture from integer to numeric
ALTER TABLE public.sensor_readings 
ALTER COLUMN soil_moisture TYPE numeric(5,2);

-- Fix 2: Add missing columns for temperature/humidity/flow
ALTER TABLE public.sensor_readings 
  ADD COLUMN IF NOT EXISTS temperature_c numeric(5,2),
  ADD COLUMN IF NOT EXISTS flow_litres numeric(7,3);

-- Fix 3: Add last_seen column to devices (for fault detector)
ALTER TABLE public.devices 
  ADD COLUMN IF NOT EXISTS last_seen timestamptz;

-- Fix 4: Enable realtime on sensor_readings
ALTER PUBLICATION supabase_realtime ADD TABLE public.sensor_readings;

//q28
INSERT INTO sensor_readings (
  device_id, 
  soil_moisture, 
  temperature_c, 
  humidity, 
  flow_litres, 
  rain_detected,
  recorded_at
) 
VALUES 
  -- Generate 20 readings over time
  ('e27d7437-eb5c-44f4-b826-d4ffdbadb6aa', 45.0, 25.5, 60.0, 2.5, false, NOW() - INTERVAL '95 minutes'),
  ('e27d7437-eb5c-44f4-b826-d4ffdbadb6aa', 46.2, 25.8, 61.0, 2.3, false, NOW() - INTERVAL '90 minutes'),
  ('e27d7437-eb5c-44f4-b826-d4ffdbadb6aa', 47.5, 26.0, 59.0, 2.8, false, NOW() - INTERVAL '85 minutes'),
  ('e27d7437-eb5c-44f4-b826-d4ffdbadb6aa', 48.1, 26.2, 58.0, 2.6, false, NOW() - INTERVAL '80 minutes'),
  ('e27d7437-eb5c-44f4-b826-d4ffdbadb6aa', 49.0, 26.5, 57.0, 2.4, false, NOW() - INTERVAL '75 minutes'),
  ('e27d7437-eb5c-44f4-b826-d4ffdbadb6aa', 50.2, 26.8, 56.0, 2.7, false, NOW() - INTERVAL '70 minutes'),
  ('e27d7437-eb5c-44f4-b826-d4ffdbadb6aa', 51.5, 27.0, 55.0, 2.5, false, NOW() - INTERVAL '65 minutes'),
  ('e27d7437-eb5c-44f4-b826-d4ffdbadb6aa', 52.0, 27.2, 54.0, 2.3, false, NOW() - INTERVAL '60 minutes'),
  ('e27d7437-eb5c-44f4-b826-d4ffdbadb6aa', 52.8, 27.5, 53.0, 2.6, false, NOW() - INTERVAL '55 minutes'),
  ('e27d7437-eb5c-44f4-b826-d4ffdbadb6aa', 53.5, 27.8, 52.0, 2.4, false, NOW() - INTERVAL '50 minutes'),
  ('e27d7437-eb5c-44f4-b826-d4ffdbadb6aa', 54.0, 28.0, 51.0, 2.8, false, NOW() - INTERVAL '45 minutes'),
  ('e27d7437-eb5c-44f4-b826-d4ffdbadb6aa', 54.5, 28.2, 50.0, 2.5, false, NOW() - INTERVAL '40 minutes'),
  ('e27d7437-eb5c-44f4-b826-d4ffdbadb6aa', 55.0, 28.5, 49.0, 2.3, false, NOW() - INTERVAL '35 minutes'),
  ('e27d7437-eb5c-44f4-b826-d4ffdbadb6aa', 55.8, 28.8, 48.0, 2.7, false, NOW() - INTERVAL '30 minutes'),
  ('e27d7437-eb5c-44f4-b826-d4ffdbadb6aa', 56.2, 29.0, 47.0, 2.6, false, NOW() - INTERVAL '25 minutes'),
  ('e27d7437-eb5c-44f4-b826-d4ffdbadb6aa', 56.8, 29.2, 46.0, 2.4, false, NOW() - INTERVAL '20 minutes'),
  ('e27d7437-eb5c-44f4-b826-d4ffdbadb6aa', 57.2, 29.5, 45.0, 2.8, false, NOW() - INTERVAL '15 minutes'),
  ('e27d7437-eb5c-44f4-b826-d4ffdbadb6aa', 57.8, 29.8, 44.0, 2.5, false, NOW() - INTERVAL '10 minutes'),
  ('e27d7437-eb5c-44f4-b826-d4ffdbadb6aa', 58.2, 30.0, 43.0, 2.3, false, NOW() - INTERVAL '5 minutes'),
  ('e27d7437-eb5c-44f4-b826-d4ffdbadb6aa', 58.5, 30.2, 42.0, 2.6, true, NOW());

//q29
-- Fix column types in sensor_readings table
ALTER TABLE sensor_readings 
ALTER COLUMN soil_moisture TYPE NUMERIC,
ALTER COLUMN temperature_c TYPE NUMERIC,
ALTER COLUMN humidity TYPE NUMERIC,
ALTER COLUMN flow_litres TYPE NUMERIC;

//q30
ALTER TABLE devices ADD COLUMN last_seen TIMESTAMP WITH TIME ZONE;

//q31
SELECT * FROM sensor_readings 
ORDER BY recorded_at DESC 
LIMIT 10;

//q32
-- Check current column types
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'sensor_readings';

//q33
ALTER TABLE sensor_readings 
ALTER COLUMN soil_moisture TYPE NUMERIC,
ALTER COLUMN temperature_c TYPE NUMERIC,
ALTER COLUMN humidity TYPE NUMERIC,
ALTER COLUMN flow_litres TYPE NUMERIC;
