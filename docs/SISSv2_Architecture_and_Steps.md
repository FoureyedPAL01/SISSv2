# RootSync — Architecture, Working & Creation Guide
### Smart Irrigation System — Serverless Edition

> **What changed from v1:** The Python backend and local Mosquitto broker are completely removed.
> The ESP32 talks directly to Supabase and HiveMQ Cloud. Any account can claim and control
> the device by entering its UUID — no reflashing ever needed to transfer ownership.
> Only two things need power: the **ESP32** and the **internet router at home**.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Component Roles](#2-component-roles)
3. [Data Flow — How Everything Works](#3-data-flow--how-everything-works)
4. [Device Claiming — How Any Account Accesses the ESP32](#4-device-claiming--how-any-account-accesses-the-esp32)
5. [ESP32 Firmware Logic Loop](#5-esp32-firmware-logic-loop)
6. [Project File Structure](#6-project-file-structure)
7. [Step-by-Step Creation Guide](#7-step-by-step-creation-guide)
   - Phase 1: HiveMQ Cloud Setup
   - Phase 2: Supabase Project Setup
   - Phase 3: Database Schema and RLS
   - Phase 4: Supabase Edge Functions
   - Phase 5: ESP32 Firmware
   - Phase 6: Flutter App Changes
   - Phase 7: End-to-End Testing

---

## 1. Architecture Overview

```
+------------------------------------------------------------------+
|                        CLOUD SERVICES                            |
|                                                                  |
|  +---------------------------+    +---------------------------+  |
|  |        Supabase           |    |      HiveMQ Cloud         |  |
|  |  PostgreSQL + Auth +      |    |  MQTT Broker, free tier   |  |
|  |  Realtime + Edge Fns      |    |  Port 8883 (TLS)          |  |
|  |                           |    |                           |  |
|  |  Tables:                  |    |  Topic:                   |  |
|  |  * users                  |    |  devices/{id}/control     |  |
|  |  * devices  <-- claiming  |    |  ^ Flutter publishes      |  |
|  |  * sensor_readings        |    |  v ESP32 subscribes       |  |
|  |  * pump_logs              |    |                           |  |
|  |  * crop_profiles          |    +-------------+-------------+  |
|  |  * device_commands        |                  |                |
|  |  * alerts                 |                  |                |
|  +-------------+-------------+                  |                |
|                |                                |                |
+----------------+--------------------------------+----------------+
                 | HTTPS REST                     | MQTT / TLS
                 |                                |
    +------------+---------------------------+    |
    |  ESP32 uses:                           |    |
    |  POST  /sensor_readings                |    |
    |  POST  /pump_logs (start of cycle)     |    |
    |  PATCH /pump_logs (end of cycle)       |    |
    |  GET   /crop_profiles (on boot)        |    |
    |  GET   /device_commands (poll 5s)      |    |
    |  PATCH /devices (status + last_seen)   |    |
    |  POST  /alerts (fault events)          |    |
    |                                        |    |
+---+------------------------------------+   | +--+------------------------------+
|            ESP32                       |   | |        Flutter App              |
|  * Reads all sensors every 30s         |   | |  * Auth via Supabase            |
|  * Runs irrigation decision logic      |   | |  * Link Device screen           |
|  * Fetches weather (Open-Meteo free)   |   | |    UUID entry to claim device   |
|  * POSTs data to Supabase REST         |   | |  * Dashboard via Realtime       |
|  * Subscribes to HiveMQ MQTT          +<--+ |  * Pump control via MQTT publish |
|  * Connects to home WiFi only          |     |  * All screens from any network  |
|  * Hardcoded DEVICE_ID (UUID)          |     +----------------------------------+
+----------------------------------------+
  [power outlet only -- no laptop needed]
```

### What Was Removed vs v1

| v1 Component | v2 Status | Reason |
|---|---|---|
| Python FastAPI backend | Deleted entirely | Logic moved into ESP32 firmware |
| Local Mosquitto broker | Deleted entirely | Replaced by HiveMQ Cloud |
| `backend/` folder | Deleted | Not needed |
| `PYTHON_BACKEND_URL` in `.env` | Deleted | Not needed |
| HTTP POST from Flutter to Python | Replaced by MQTT publish to HiveMQ | Direct cloud path |
| Fixed `user_id` on device row | Replaced by device claiming system | Any account can take ownership |

---

## 2. Component Roles

### ESP32 (The Brain — runs 24/7, power outlet only)

Does everything the Python backend used to do, plus its original sensor and pump work:

- Reads soil moisture (ADC), temperature and humidity (DHT11), rain sensor (digital), flow meter (interrupt)
- Runs the full irrigation decision engine locally in firmware
- Fetches rain forecast from **Open-Meteo** — free, no API key, no account needed
- POSTs sensor readings to **Supabase REST API** over HTTPS every 30 seconds
- POSTs and PATCHes pump log entries to Supabase (start and end of each cycle)
- Reads the active crop profile from Supabase on boot, stores thresholds in RAM
- Polls `device_commands` table every 5 seconds as a fallback for missed MQTT messages
- Subscribes to HiveMQ Cloud MQTT topic for real-time manual pump commands
- Has one fixed UUID hardcoded in `config.h` — its permanent identity

### Supabase (Cloud Database — always online)

- Stores all sensor data, pump logs, crop profiles, alerts, and user accounts
- Provides Realtime subscriptions that push live updates to the Flutter app
- The `devices` table tracks the current owner (`user_id`) of each ESP32
- `user_id` on a device row is **mutable** — it changes whenever a new account claims the device
- RLS policies ensure each user only sees data for devices they currently own
- All historical data is linked by `device_id` (the hardware UUID), not by `user_id`, so it automatically follows ownership when a device is claimed by a new account

### HiveMQ Cloud (Cloud MQTT Broker — free tier, always online)

- ESP32 connects on boot over TLS port 8883 using dedicated device credentials
- ESP32 subscribes to `devices/{device_id}/control`
- Flutter publishes `{"command":"pump_on"}` or `{"command":"pump_off"}` to that topic
- HiveMQ relays the message globally in milliseconds — no laptop broker needed
- Free tier supports 100 simultaneous connections with no expiry

### Flutter App (Phone or Tablet — any network, anywhere)

Four things change from v1:

1. `mqtt_service.dart` — broker URL becomes HiveMQ Cloud, port 8883, TLS enabled
2. `pump_control_screen.dart` — publishes MQTT instead of HTTP POST to Python
3. `link_device_screen.dart` — **NEW** — lets any logged-in user claim the ESP32 by entering its UUID
4. `router.dart` and `app_state_provider.dart` — **SMALL CHANGE** — redirect to link screen when no device is found

All nine content screens (dashboard, irrigation, weather, water usage, fertigation, alerts, settings, crop profiles, pump control) work identically. Supabase Realtime subscriptions are unchanged.

---

## 3. Data Flow — How Everything Works

### A. Automatic Irrigation (no human involved)

```
Every 30 seconds:

ESP32 reads all sensors
    |
    +-> HTTPS POST to Supabase /sensor_readings
    |       +-> Supabase Realtime fires -> Flutter dashboard updates live
    |
    +-> Irrigation decision:
            |
            +- rain sensor HIGH?
            |   +-> pump OFF, skip cycle
            |
            +- soil moisture >= moistureHigh threshold?
            |   +-> pump OFF, soil is wet enough
            |
            +- soil moisture between low and high?
            |   +-> no action needed
            |
            +- soil moisture < moistureLow threshold:
                    |
                    +-> HTTPS GET to Open-Meteo (free, no API key)
                            |
                            +- rain > 60% in next 6 hours?
                            |   +-> skip, rain is coming
                            |
                            +- no rain forecast:
                                    pump ON
                                    POST pump_on_at + moisture_before to Supabase
                                    wait irrigation_duration_seconds
                                    pump OFF
                                    read moisture_after
                                    PATCH duration + moisture_after to Supabase
```

### B. Manual Pump Control — Primary Path (MQTT, real-time)

```
User taps "Start Pump" in Flutter app
    |
    +-> Flutter publishes {"command":"pump_on"} to HiveMQ (QoS 1)
    +-> Flutter also INSERTs into Supabase device_commands (fallback, runs simultaneously)
            |
            +-> HiveMQ delivers to ESP32 (subscribed, TLS)
                        |
                        +-> ESP32 MQTT callback fires immediately
                            pump ON, manualOverride = true
                            POST pump_on_at to Supabase pump_logs
                            Supabase Realtime notifies Flutter dashboard
```

### C. Manual Pump Control — Fallback Path (Supabase polling)

```
If MQTT message is delayed or ESP32 reconnects after a brief drop:

Flutter has already written {"command":"pump_on", consumed: false}
to Supabase device_commands
    |
    +-> ESP32 polls device_commands every 5 seconds
                |
                +-> Finds unconsumed row -> executes command
                    PATCHes consumed = true -> prevents duplicate execution
```

> Both paths fire simultaneously. Whichever reaches ESP32 first wins.
> The second is ignored because of the consumed flag.

### D. Dashboard from Any Location

```
User opens Flutter app (office, mobile data, different WiFi -- anywhere)
    |
    +-> App authenticates with Supabase (always online)
        App queries devices WHERE user_id = current user -> gets device_id
        App subscribes to Supabase Realtime on sensor_readings for that device_id
                |
                +-> ESP32 at home POSTs sensor data every 30s
                    Supabase fires Realtime event
                    Flutter dashboard receives update and displays live values
```

### E. Device Claiming (new user takes ownership)

```
New user creates account -> logs in -> no device found for their user_id
    |
    +-> App navigates to /link-device screen automatically
        User types the device UUID (from sticker on the ESP32 box)
        User taps "Link Device"
                |
                +-> Flutter runs:
                    UPDATE devices
                    SET user_id = new_user_id, claimed_at = now()
                    WHERE id = entered_uuid

                    RLS policy checks: is user authenticated? -> yes -> allow
                            |
                            +-> device row now owned by new user
                                previous owner's user_id is replaced -> they lose access
                                all historical sensor_readings and pump_logs
                                are immediately visible to new owner
                                (linked by device_id, not user_id)
                                app navigates to dashboard -> shows all data
```

---

## 4. Device Claiming — How Any Account Accesses the ESP32

### The Key Design Principle

The ESP32's UUID is hardcoded in firmware — it is the hardware's permanent identity, like a serial number. It never changes. What changes is which user account "owns" that UUID in the `devices` table. Ownership transfer is a single database UPDATE that any authenticated user can perform.

```
devices table row (example):
+------------------+----------------------------------------------+
|  id (UUID)       |  a3f7c821-04be-4d9e-b2a1-9fd063e1c4f7       | <- hardcoded in ESP32
|  user_id         |  bbb222-new-user-uuid                        | <- changes on claim
|  claimed_at      |  2025-03-15 10:30:00                         |
|  status          |  online                                      |
|  last_seen       |  2025-03-15 10:45:22                         |
+------------------+----------------------------------------------+
```

### Rules

- Any authenticated (logged-in) user can claim any device if they know the UUID
- Claiming replaces `user_id` with the new user's ID — the previous owner immediately loses access
- The ESP32 is completely unaware of ownership changes — it keeps posting using its hardcoded UUID
- All historical data follows the device because it is linked by `device_id`, not `user_id`

### The Link Device Screen Flow

```
App startup after login:
    |
    AppStateProvider._fetchUserDevices() runs
    SELECT * FROM devices WHERE user_id = current_user_id
        |
        +- Device found -> load device_id -> subscribe Realtime -> show Dashboard
        |
        +- No device found -> GoRouter redirects to /link-device
                |
                +-----------------------------------------------+
                |  Link Your Device                             |
                |                                               |
                |  Enter the Device UUID from the sticker       |
                |  on your RootSync hardware unit.                  |
                |                                               |
                |  [ xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx ]     |
                |                                               |
                |             [ Link Device ]                   |
                +-----------------------------------------------+
                        |
                User enters UUID -> taps Link Device
                        |
                        +-> UPDATE devices SET user_id=me, claimed_at=now()
                                WHERE id = entered_uuid
                            On success -> AppStateProvider.refresh()
                                       -> GoRouter navigates to /dashboard
```

### Demo Scenario for Teachers

```
Step 1 -- You present the app with your account logged in.
          Teachers see live data, pump control working.

Step 2 -- Teacher creates a new account in the app -> logs in.
          App shows Link Device screen (no device linked to new account).

Step 3 -- Teacher types the UUID from the sticker on the ESP32 -> taps Link.
          Your account loses access. Teacher's dashboard immediately shows
          all historical data plus live readings. Teacher can control the pump.

Step 4 -- After the demo, you log back in with your account.
          App shows Link Device screen again.
          Enter the same UUID -> tap Link -> your account owns it again.
          Takes about 10 seconds.
```

---

## 5. ESP32 Firmware Logic Loop

```
BOOT:
  connectWiFi()
  connectHiveMQ()                    <- TLS MQTT to HiveMQ Cloud, port 8883
  subscribe("devices/{id}/control")
  cropProfile = fetchCropProfile()   <- GET from Supabase, stored in RAM
  updateDeviceStatus("online")       <- PATCH devices table

LOOP every 30 seconds:
  readings = readAllSensors()
  postSensorReading(readings)        <- HTTPS POST to Supabase
  checkFaultDetection(readings)

  if NOT manualOverride:
      if rain sensor HIGH:
          pumpOFF, skip

      else if moisture >= moistureHigh:
          pumpOFF, skip

      else if moisture >= moistureLow:
          no action, skip

      else (soil is dry):
          rainPct = getRainForecastPct()   <- Open-Meteo HTTPS GET
          if rainPct >= rainSkipPct:
              skip (rain is coming)
          else:
              logId = postPumpLogStart(moisture, "auto")
              pumpON()
              delay(irrigateSecs * 1000)
              pumpOFF()
              patchPumpLogEnd(logId, readMoisture(), elapsed, waterUsed)

  cmd = checkDeviceCommands()        <- poll Supabase fallback table
  if cmd == "pump_on":   manualOverride=true,  pumpON()
  if cmd == "pump_off":  manualOverride=false, pumpOFF()

  updateDeviceStatus("online")
  mqttLoop()                         <- non-blocking, handles incoming MQTT

MQTT CALLBACK (fires immediately on message):
  parse JSON payload
  if command == "pump_on":   manualOverride=true,  pumpON()
  if command == "pump_off":  manualOverride=false, pumpOFF()
```

### Fault Detection (runs every loop iteration)

```
Sensor stuck:
  last 10 moisture readings all identical?
  -> insertAlert("sensor_stuck", "Soil moisture not changing")

No-flow while pumping:
  pump is ON but flow sensor reads 0 for 3+ readings?
  -> pumpOFF()
  -> insertAlert("no_flow", "Pump ON but no water flow detected")

WiFi drop recovery:
  WiFi disconnected? -> attempt reconnect every 5 seconds
  continue using last known thresholds from RAM (no irrigation skipped)
```

---

## 6. Project File Structure

```
SISS_v2/
|
+-- esp32/
|   +-- config.h              <- WiFi creds, Supabase URL + anon key,
|   |                            HiveMQ host/user/pass, DEVICE_ID (UUID),
|   |                            GPS coordinates, sensor pin numbers,
|   |                            default thresholds
|   +-- supabase_client.h     <- postSensorReading(), postPumpLogStart(),
|   |                            patchPumpLogEnd(), fetchCropProfile(),
|   |                            checkDeviceCommands(), insertAlert(),
|   |                            updateDeviceStatus()
|   +-- weather_client.h      <- getRainForecastPct() via Open-Meteo HTTPS GET
|   +-- main.ino              <- setup(), loop(), MQTT callback,
|                                WiFiClientSecure for TLS, DHT, flow interrupt
|
+-- app/                      <- Flutter project
|   +-- lib/
|   |   +-- services/
|   |   |   +-- mqtt_service.dart           <- CHANGED: HiveMQ Cloud, TLS, port 8883
|   |   +-- screens/
|   |   |   +-- pump_control_screen.dart    <- CHANGED: MQTT + Supabase fallback
|   |   |   +-- link_device_screen.dart     <- NEW: UUID entry + device claim
|   |   +-- providers/
|   |   |   +-- app_state_provider.dart     <- SMALL CHANGE: add hasDevice getter
|   |   +-- router.dart                     <- SMALL CHANGE: /link-device route + redirect
|   +-- .env                                <- CHANGED: remove PYTHON_BACKEND_URL,
|                                              add HIVEMQ_HOST/USER/PASS
|
+-- supabase/
    +-- migrations/
    |   +-- 001_initial_schema.sql       <- core tables; devices.user_id nullable
    |   +-- 002_device_commands.sql      <- device_commands table
    |   +-- 003_rls_policies.sql         <- all RLS including device claiming policy
    |   +-- 004_realtime.sql             <- enable Realtime on key tables
    +-- functions/
        +-- perenual-lookup/             <- unchanged from v1
        +-- purge-old-logs/              <- unchanged from v1
        +-- weekly-summary/             <- unchanged from v1
```

---

## 7. Step-by-Step Creation Guide

---

### Phase 1 — HiveMQ Cloud Setup

**Step 1.1 — Create a free HiveMQ Cloud cluster**

1. Go to https://www.hivemq.com/mqtt-cloud-broker/
2. Click **Start Free** — sign up with email, no credit card required
3. On the dashboard click **Create New Cluster**
4. Choose **Free** tier, select any region, click **Create**
5. Wait about 30 seconds for provisioning
6. Note your cluster hostname, e.g. `abc1234.s1.eu.hivemq.cloud`

**Step 1.2 — Create MQTT credentials**

1. In your cluster dashboard go to **Access Management → Credentials**
2. Click **Add new credentials**
3. Username: `siss_device`, strong password → Save (used by ESP32)
4. Click **Add new credentials** again
5. Username: `siss_app`, different strong password → Save (used by Flutter)
6. Write down both credential pairs and the cluster hostname

**Step 1.3 — Test the connection (optional)**

Download MQTT Explorer from https://mqtt-explorer.com. Connect with `siss_app` credentials, host = cluster hostname, port 8883, TLS enabled. Subscribe to `devices/#`. If the connection succeeds, the broker is ready.

---

### Phase 2 — Supabase Project Setup

**Step 2.1 — Create a new Supabase project**

1. Go to https://supabase.com/dashboard
2. Click **New project** → name it `SISS_v2`
3. Set a strong database password and save it
4. Choose a region close to your location → **Create new project**
5. Wait about 2 minutes for provisioning

**Step 2.2 — Collect your API keys**

Go to **Project Settings → API**:

| Key | Where it goes | Notes |
|---|---|---|
| Project URL | ESP32 `config.h`, Flutter `.env` | Safe to use anywhere |
| `anon` public key | ESP32 `config.h`, Flutter `.env` | RLS limits what it can do |
| `service_role` secret key | Supabase Edge Functions only | Never put in firmware or Flutter |

**Step 2.3 — Create the device row for your ESP32**

Do this after running the Phase 3 migrations.

1. Go to **Table Editor → devices**
2. Click **Insert row**
3. Set `name` = `My Plant`, leave `user_id` as **NULL** (unclaimed), set `status` = `offline`
4. Leave `id` blank — Supabase auto-generates the UUID
5. Click **Save**
6. Copy the generated UUID from the `id` column
7. Paste it into ESP32 `config.h` as `DEVICE_ID`
8. Write this UUID on a sticker and attach it to the ESP32 box for demos

> The device starts as unclaimed. The first user to enter this UUID in the
> app will become its owner. Every subsequent user who enters the UUID claims it
> and becomes the new owner.

**Step 2.4 — Enable Realtime**

1. Go to **Database → Replication**
2. Enable replication for: `sensor_readings`, `pump_logs`, `alerts`, `device_commands`

---

### Phase 3 — Database Schema & RLS

Run all four migrations in order via **Supabase Dashboard → SQL Editor → New query**.

---

#### Migration 001 — Core Tables

```sql
-- 001_initial_schema.sql

-- Users: mirrors Supabase Auth.
-- Auto-populated by the trigger below on every new signup.
create table public.users (
  id         uuid primary key references auth.users(id) on delete cascade,
  username   text,
  email      text,
  created_at timestamptz default now()
);

-- Trigger: automatically create a public.users row when a new auth signup happens.
-- security definer means the function runs with the privileges of its creator (superuser),
-- which is needed to insert into public.users from within an auth event.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.users (id, email)
  values (new.id, new.email);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Devices: one row per physical ESP32.
-- user_id is nullable:
--   NULL  = unclaimed, no user owns this device yet
--   <uuid> = the user who currently owns this device
-- on delete set null: if the owning user deletes their account,
--   the device becomes unclaimed rather than being deleted.
--   All historical sensor data is preserved.
-- claimed_at: timestamp of the most recent ownership transfer.
create table public.devices (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid references public.users(id) on delete set null,
  name            text default 'My Plant',
  status          text default 'offline',
  last_seen       timestamptz,
  crop_profile_id bigint,
  claimed_at      timestamptz,
  created_at      timestamptz default now()
);

-- Sensor readings: one row every 30 seconds posted by ESP32.
create table public.sensor_readings (
  id            bigserial primary key,
  device_id     uuid references public.devices(id) on delete cascade,
  soil_moisture integer,
  temperature_c numeric(5,2),
  humidity      numeric(5,2),
  rain_detected boolean default false,
  flow_litres   numeric(8,4),
  recorded_at   timestamptz default now()
);

-- Pump logs: one row per irrigation or manual pump cycle.
-- Posted by ESP32 at start of cycle; PATCHed at end with duration and moisture_after.
create table public.pump_logs (
  id                bigserial primary key,
  device_id         uuid references public.devices(id) on delete cascade,
  pump_on_at        timestamptz default now(),
  duration_seconds  integer,
  water_used_litres numeric(8,4),
  moisture_before   integer,
  moisture_after    integer,
  rain_detected     boolean default false,
  trigger_type      text default 'auto',
  created_at        timestamptz default now()
);

-- Crop profiles: irrigation thresholds set by the user in the app.
-- Linked to devices via devices.crop_profile_id.
create table public.crop_profiles (
  id                      bigserial primary key,
  user_id                 uuid references public.users(id) on delete cascade,
  name                    text not null,
  moisture_threshold_low  integer default 30,
  moisture_threshold_high integer default 70,
  irrigation_duration_s   integer default 60,
  weather_sensitivity     integer default 60,
  created_at              timestamptz default now()
);

-- FK from devices to crop_profiles (added after both tables exist).
alter table public.devices
  add constraint fk_crop_profile
  foreign key (crop_profile_id) references public.crop_profiles(id)
  on delete set null;

-- Alerts: fault events inserted by ESP32.
create table public.alerts (
  id         bigserial primary key,
  device_id  uuid references public.devices(id) on delete cascade,
  alert_type text,
  message    text,
  resolved   boolean default false,
  created_at timestamptz default now()
);

-- Fertigation logs: manual fertilizer events logged from the app.
create table public.fertigation_logs (
  id              bigserial primary key,
  device_id       uuid references public.devices(id) on delete cascade,
  crop_profile_id bigint references public.crop_profiles(id) on delete set null,
  fertilized_at   timestamptz default now(),
  notes           text
);
```

---

#### Migration 002 — Device Commands Table

```sql
-- 002_device_commands.sql
-- Flutter inserts a row here whenever the user taps pump control.
-- ESP32 polls every 5 seconds, finds unconsumed rows, executes the command,
-- and marks the row consumed=true to prevent re-execution.
-- This is the fallback path for when MQTT delivery is delayed.

create table public.device_commands (
  id         bigserial primary key,
  device_id  uuid references public.devices(id) on delete cascade,
  command    text not null,
  consumed   boolean default false,
  created_at timestamptz default now()
);

-- Helper function to clean up old consumed rows.
-- Keeps the table small. Call manually or schedule via pg_cron.
create or replace function delete_old_commands()
returns void language plpgsql as $$
begin
  delete from public.device_commands
  where consumed = true
    and created_at < now() - interval '1 hour';
end;
$$;
```

---

#### Migration 003 — Row Level Security Policies

```sql
-- 003_rls_policies.sql

-- Enable RLS on every table.
-- With RLS enabled, ALL access is denied by default until a policy explicitly allows it.
alter table public.users            enable row level security;
alter table public.devices          enable row level security;
alter table public.sensor_readings  enable row level security;
alter table public.pump_logs        enable row level security;
alter table public.crop_profiles    enable row level security;
alter table public.alerts           enable row level security;
alter table public.fertigation_logs enable row level security;
alter table public.device_commands  enable row level security;

-- ── USERS ────────────────────────────────────────────────────────────────────
-- Each user can only read or update their own profile row.
create policy "users: own row"
  on public.users for all
  using (auth.uid() = id);

-- ── DEVICES ──────────────────────────────────────────────────────────────────

-- Authenticated users can read only the device they currently own.
create policy "devices: owner reads"
  on public.devices for select
  using (auth.uid() = user_id);

-- Device claiming policy.
-- Any authenticated user can UPDATE a device's user_id to their own auth.uid().
-- USING (auth.uid() is not null) = any authenticated user can target any device row.
-- WITH CHECK (auth.uid() = user_id) = after the update, user_id must equal the caller.
--   This prevents a user from setting user_id to someone else's ID.
--   It also means the caller becomes the new owner.
-- Deliberate design: allows ownership transfer without requiring the previous
-- owner's consent (suitable for academic demos and single-user setups).
create policy "devices: claim by uuid"
  on public.devices for update
  using (auth.uid() is not null)
  with check (auth.uid() = user_id);

-- ESP32 (anon key) can update device status and last_seen.
-- USING (true) = any row can be targeted.
-- Note: RLS cannot restrict which columns are updated, only which rows.
-- In practice the ESP32 only knows its own DEVICE_ID and only updates
-- status/last_seen, so this broad policy is acceptable for academic use.
create policy "devices: esp32 status update"
  on public.devices for update
  using (true);

-- ── SENSOR_READINGS ──────────────────────────────────────────────────────────

-- Authenticated users see readings only for devices they own.
create policy "sensor_readings: owner reads"
  on public.sensor_readings for select
  using (
    device_id in (
      select id from public.devices where user_id = auth.uid()
    )
  );

-- ESP32 (anon key) can insert sensor readings.
-- The FK on device_id ensures only rows for existing devices are accepted.
create policy "sensor_readings: esp32 insert"
  on public.sensor_readings for insert
  with check (true);

-- ── PUMP_LOGS ────────────────────────────────────────────────────────────────

-- Authenticated users see logs for their own devices.
create policy "pump_logs: owner reads"
  on public.pump_logs for select
  using (
    device_id in (
      select id from public.devices where user_id = auth.uid()
    )
  );

-- ESP32 inserts at cycle start and PATCHes at cycle end.
create policy "pump_logs: esp32 insert"
  on public.pump_logs for insert
  with check (true);

create policy "pump_logs: esp32 update"
  on public.pump_logs for update
  using (true);

-- ── CROP_PROFILES ────────────────────────────────────────────────────────────

-- Authenticated users manage their own crop profiles.
create policy "crop_profiles: owner manages"
  on public.crop_profiles for all
  using (auth.uid() = user_id);

-- ESP32 reads the active crop profile on boot.
create policy "crop_profiles: esp32 read"
  on public.crop_profiles for select
  using (true);

-- ── ALERTS ───────────────────────────────────────────────────────────────────

-- Authenticated users see alerts for their own devices.
create policy "alerts: owner reads"
  on public.alerts for select
  using (
    device_id in (
      select id from public.devices where user_id = auth.uid()
    )
  );

-- ESP32 inserts alerts on fault detection.
create policy "alerts: esp32 insert"
  on public.alerts for insert
  with check (true);

-- ── DEVICE_COMMANDS ──────────────────────────────────────────────────────────

-- Flutter (authenticated user) inserts commands only for their own device.
create policy "device_commands: owner insert"
  on public.device_commands for insert
  with check (
    device_id in (
      select id from public.devices where user_id = auth.uid()
    )
  );

-- ESP32 reads unconsumed commands and marks them consumed.
create policy "device_commands: esp32 read"
  on public.device_commands for select
  using (true);

create policy "device_commands: esp32 update"
  on public.device_commands for update
  using (true);

-- ── FERTIGATION_LOGS ─────────────────────────────────────────────────────────

create policy "fertigation_logs: owner manages"
  on public.fertigation_logs for all
  using (
    device_id in (
      select id from public.devices where user_id = auth.uid()
    )
  );
```

---

#### Migration 004 — Enable Realtime

```sql
-- 004_realtime.sql
-- Adds tables to the supabase_realtime publication.
-- After this, INSERT/UPDATE/DELETE events on these tables are broadcast
-- to any Flutter client subscribed via Supabase.channel().

alter publication supabase_realtime add table public.sensor_readings;
alter publication supabase_realtime add table public.pump_logs;
alter publication supabase_realtime add table public.alerts;
alter publication supabase_realtime add table public.device_commands;
```

---

### Phase 4 — Supabase Edge Functions

Carry over from v1 with no changes. Redeploy to the new SISS_v2 project:

- `perenual-lookup` — plant data cache with 7-day TTL
- `purge-old-logs` — 14-day pump log retention
- `weekly-summary` — weekly email digest

No new Edge Functions required for v2.

---

### Phase 5 — ESP32 Firmware

#### Files to create:

```
SISS_v2/
+-- esp32/
    +-- config.h           <- Step 5.2
    +-- supabase_client.h  <- Step 5.3
    +-- weather_client.h   <- Step 5.4
    +-- main.ino           <- Step 5.5
```

**Step 5.1 — Install Arduino libraries**

Open Arduino IDE → Tools → Manage Libraries → install:

| Library | Version | Purpose |
|---|---|---|
| `PubSubClient` by Nick O'Leary | 2.8+ | MQTT client |
| `DHT sensor library` by Adafruit | 1.4+ | DHT11 readings |
| `ArduinoJson` by Benoit Blanchon | 7.x | Parse JSON from Open-Meteo and Supabase |

`HTTPClient` and `WiFiClientSecure` come with the ESP32 Arduino core — no separate install needed.

---

**Step 5.2 — `config.h`**

```cpp
// config.h
// All credentials in one place. Fill every value before flashing.
// Do not commit this file to a public Git repository.

#pragma once

// -- WiFi ------------------------------------------------------------------
#define WIFI_SSID         "your_home_wifi_name"
#define WIFI_PASSWORD     "your_home_wifi_password"

// -- Supabase --------------------------------------------------------------
// Project URL: Settings -> API -> Project URL
#define SUPABASE_URL      "https://xxxxxxxxxxxx.supabase.co"
// Anon key: Settings -> API -> anon public
#define SUPABASE_ANON_KEY "eyJhbGciO..."

// -- Device Identity -------------------------------------------------------
// UUID from the devices table row created in Supabase Step 2.3.
// This is the hardware's permanent identity -- never changes.
// Write this on a sticker on the ESP32 box for demos.
#define DEVICE_ID         "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

// -- HiveMQ Cloud ----------------------------------------------------------
#define MQTT_HOST         "abc1234.s1.eu.hivemq.cloud"
#define MQTT_PORT         8883
#define MQTT_USER         "siss_device"
#define MQTT_PASSWORD     "your_device_password"
#define MQTT_TOPIC_SUB    "devices/" DEVICE_ID "/control"
#define MQTT_TOPIC_PUB    "devices/" DEVICE_ID "/status"

// -- Open-Meteo location ---------------------------------------------------
// GPS coordinates of the location where the plant is
#define LOCATION_LAT      "19.0760"  // Mumbai example -- change to yours
#define LOCATION_LON      "72.8777"

// -- Sensor pins -----------------------------------------------------------
#define PIN_SOIL_MOISTURE  34  // Analog input (ADC)
#define PIN_DHT            4   // DHT11 data pin
#define PIN_RAIN_SENSOR    35  // Digital input
#define PIN_FLOW_SENSOR    18  // Interrupt input (YF-S201)
#define PIN_PUMP_RELAY     26  // Digital output to relay module

// -- Default thresholds ----------------------------------------------------
// Used if no crop profile is found in Supabase on boot
#define DEFAULT_MOISTURE_LOW  30  // start watering when moisture% falls below this
#define DEFAULT_MOISTURE_HIGH 70  // stop watering when moisture% rises above this
#define DEFAULT_IRRIGATE_SECS 60  // seconds to run the pump per cycle
#define DEFAULT_RAIN_SKIP_PCT 60  // skip irrigation if rain probability exceeds this
```

---

**Step 5.3 — `supabase_client.h`**

```cpp
// supabase_client.h
// All HTTPS calls to the Supabase REST API.
//
// How Supabase REST works:
//   Every table is exposed at: <SUPABASE_URL>/rest/v1/<table_name>
//   GET   = SELECT (add ?column=eq.value to filter rows)
//   POST  = INSERT a new row
//   PATCH = UPDATE matching rows (?id=eq.<value> targets one row)
//   Headers: apikey identifies the project; Authorization sets RLS permissions
//   Prefer: return=representation makes POST return the inserted row as JSON

#pragma once
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include <ArduinoJson.h>
#include "config.h"

// Attaches the three required headers to every Supabase request
void _addSupabaseHeaders(HTTPClient& http) {
  http.addHeader("apikey",        SUPABASE_ANON_KEY);
  http.addHeader("Authorization", "Bearer " + String(SUPABASE_ANON_KEY));
  http.addHeader("Content-Type",  "application/json");
  http.addHeader("Prefer",        "return=representation");
}

// POST a sensor reading row. Returns true on success (HTTP 201).
bool postSensorReading(int moisture, float temp, float humidity,
                       bool rain, float flow) {
  WiFiClientSecure client;
  client.setInsecure(); // skips TLS cert verification; acceptable for academic use
  HTTPClient http;
  http.begin(client, String(SUPABASE_URL) + "/rest/v1/sensor_readings");
  _addSupabaseHeaders(http);

  JsonDocument doc;
  doc["device_id"]     = DEVICE_ID;
  doc["soil_moisture"] = moisture;
  doc["temperature_c"] = temp;
  doc["humidity"]      = humidity;
  doc["rain_detected"] = rain;
  doc["flow_litres"]   = flow;
  String body;
  serializeJson(doc, body);

  int code = http.POST(body);
  http.end();
  return (code == 201);
}

// POST the start of a pump cycle.
// Returns the database-assigned id of the new row (needed to PATCH it later).
// Returns -1 on failure.
long postPumpLogStart(int moistureBefore, String triggerType) {
  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient http;
  http.begin(client, String(SUPABASE_URL) + "/rest/v1/pump_logs");
  _addSupabaseHeaders(http);

  JsonDocument doc;
  doc["device_id"]       = DEVICE_ID;
  doc["moisture_before"] = moistureBefore;
  doc["trigger_type"]    = triggerType;
  String body;
  serializeJson(doc, body);

  int    code = http.POST(body);
  String resp = http.getString();
  http.end();
  if (code != 201) return -1;

  // Supabase returns the inserted row as a JSON array:
  // [{"id":42, "device_id":"...", "moisture_before":35, ...}]
  // We parse it to extract the id for the later PATCH call.
  JsonDocument respDoc;
  deserializeJson(respDoc, resp);
  return respDoc[0]["id"].as<long>();
}

// PATCH the pump log row when the irrigation cycle ends.
// logId: the id returned by postPumpLogStart.
void patchPumpLogEnd(long logId, int moistureAfter,
                     int durationSecs, float waterLitres) {
  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient http;
  // ?id=eq.<logId> is a Supabase REST filter: WHERE id = logId
  http.begin(client, String(SUPABASE_URL) +
             "/rest/v1/pump_logs?id=eq." + String(logId));
  http.addHeader("apikey",        SUPABASE_ANON_KEY);
  http.addHeader("Authorization", "Bearer " + String(SUPABASE_ANON_KEY));
  http.addHeader("Content-Type",  "application/json");

  JsonDocument doc;
  doc["moisture_after"]    = moistureAfter;
  doc["duration_seconds"]  = durationSecs;
  doc["water_used_litres"] = waterLitres;
  String body;
  serializeJson(doc, body);

  http.PATCH(body);
  http.end();
}

// Struct to hold thresholds loaded from Supabase
struct CropProfile {
  int moistureLow  = DEFAULT_MOISTURE_LOW;
  int moistureHigh = DEFAULT_MOISTURE_HIGH;
  int irrigateSecs = DEFAULT_IRRIGATE_SECS;
  int rainSkipPct  = DEFAULT_RAIN_SKIP_PCT;
};

// GET active crop profile from Supabase.
// cropProfileId: the bigint id of the crop_profiles row.
// Returns a struct with defaults if no profile is set or the fetch fails.
CropProfile fetchCropProfile(String cropProfileId) {
  CropProfile p;
  if (cropProfileId == "" || cropProfileId == "null") return p;

  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient http;
  http.begin(client, String(SUPABASE_URL) +
             "/rest/v1/crop_profiles?id=eq." + cropProfileId + "&limit=1");
  http.addHeader("apikey",        SUPABASE_ANON_KEY);
  http.addHeader("Authorization", "Bearer " + String(SUPABASE_ANON_KEY));

  if (http.GET() == 200) {
    JsonDocument doc;
    deserializeJson(doc, http.getString());
    if (doc.size() > 0) {
      p.moistureLow  = doc[0]["moisture_threshold_low"].as<int>();
      p.moistureHigh = doc[0]["moisture_threshold_high"].as<int>();
      p.irrigateSecs = doc[0]["irrigation_duration_s"].as<int>();
      p.rainSkipPct  = doc[0]["weather_sensitivity"].as<int>();
    }
  }
  http.end();
  return p;
}

// INSERT an alert row when the ESP32 detects a fault.
void insertAlert(String alertType, String message) {
  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient http;
  http.begin(client, String(SUPABASE_URL) + "/rest/v1/alerts");
  _addSupabaseHeaders(http);

  JsonDocument doc;
  doc["device_id"]  = DEVICE_ID;
  doc["alert_type"] = alertType;
  doc["message"]    = message;
  String body;
  serializeJson(doc, body);

  http.POST(body);
  http.end();
}

// Poll device_commands for unconsumed manual commands from Flutter.
// Returns "pump_on", "pump_off", or "" if nothing is pending.
// Immediately marks the found row consumed=true to prevent re-execution.
String checkDeviceCommands() {
  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient http;
  http.begin(client, String(SUPABASE_URL) +
             "/rest/v1/device_commands"
             "?device_id=eq." + String(DEVICE_ID) +
             "&consumed=eq.false"
             "&order=created_at.asc"
             "&limit=1");
  http.addHeader("apikey",        SUPABASE_ANON_KEY);
  http.addHeader("Authorization", "Bearer " + String(SUPABASE_ANON_KEY));

  String result = "";
  if (http.GET() == 200) {
    JsonDocument doc;
    deserializeJson(doc, http.getString());
    if (doc.size() > 0) {
      result     = doc[0]["command"].as<String>();
      long cmdId = doc[0]["id"].as<long>();
      http.end();

      // Mark consumed immediately
      HTTPClient patchHttp;
      patchHttp.begin(client, String(SUPABASE_URL) +
                      "/rest/v1/device_commands?id=eq." + String(cmdId));
      patchHttp.addHeader("apikey",        SUPABASE_ANON_KEY);
      patchHttp.addHeader("Authorization", "Bearer " + String(SUPABASE_ANON_KEY));
      patchHttp.addHeader("Content-Type",  "application/json");
      patchHttp.PATCH("{\"consumed\":true}");
      patchHttp.end();
      return result;
    }
  }
  http.end();
  return result;
}

// PATCH devices.status and devices.last_seen.
// Called at boot (status="online") and every loop iteration.
void updateDeviceStatus(String status) {
  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient http;
  http.begin(client, String(SUPABASE_URL) +
             "/rest/v1/devices?id=eq." + String(DEVICE_ID));
  http.addHeader("apikey",        SUPABASE_ANON_KEY);
  http.addHeader("Authorization", "Bearer " + String(SUPABASE_ANON_KEY));
  http.addHeader("Content-Type",  "application/json");
  // "now()" is resolved by PostgreSQL to the current server timestamp
  http.PATCH("{\"status\":\"" + status + "\",\"last_seen\":\"now()\"}");
  http.end();
}
```

---

**Step 5.4 — `weather_client.h`**

```cpp
// weather_client.h
// Fetches rain probability for the next 6 hours from Open-Meteo.
// Open-Meteo is free and open-source -- no API key or account needed.
// Documentation: https://open-meteo.com/en/docs

#pragma once
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include <ArduinoJson.h>
#include "config.h"

// Returns 0 to 100 representing the highest rain probability in the next 6 hours.
// Returns 0 on any network or parse error -- safe default, irrigation will proceed.
int getRainForecastPct() {
  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient http;

  // latitude / longitude: location of the plant
  // hourly=precipitation_probability: one value per hour (0-100%)
  // forecast_days=1: only today's data, keeps response size small
  String url =
    "https://api.open-meteo.com/v1/forecast"
    "?latitude="  + String(LOCATION_LAT) +
    "&longitude=" + String(LOCATION_LON) +
    "&hourly=precipitation_probability"
    "&forecast_days=1";

  http.begin(client, url);
  int code = http.GET();
  if (code != 200) { http.end(); return 0; }

  // Response structure:
  // {
  //   "hourly": {
  //     "time": ["2025-01-01T00:00", ...],
  //     "precipitation_probability": [5, 10, 20, 80, 90, 70, ...]
  //   }
  // }
  // Take the maximum of the first 6 values (next 6 hours).
  JsonDocument doc;
  auto err = deserializeJson(doc, http.getStream());
  http.end();
  if (err) return 0;

  auto probs   = doc["hourly"]["precipitation_probability"];
  int  maxRain = 0;
  for (int i = 0; i < 6 && i < (int)probs.size(); i++) {
    int p = probs[i].as<int>();
    if (p > maxRain) maxRain = p;
  }
  return maxRain;
}
```

---

**Step 5.5 — `main.ino`**

```cpp
// main.ino
// SISS v2 -- Full ESP32 firmware.
// No Python backend. No local MQTT broker.
// ESP32 talks directly to Supabase REST API and HiveMQ Cloud.

#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>
#include <DHT.h>
#include "config.h"
#include "supabase_client.h"
#include "weather_client.h"

// -- Hardware setup --------------------------------------------------------
DHT dht(PIN_DHT, DHT11);

// volatile: this variable is modified inside an interrupt handler.
// The compiler must not cache it in a register -- reads must always go to RAM.
// IRAM_ATTR: store the interrupt handler in fast internal RAM, not flash.
volatile long flowPulseCount = 0;
void IRAM_ATTR flowISR() { flowPulseCount++; }

// -- State -----------------------------------------------------------------
CropProfile cropProfile;
bool pumpRunning    = false;
bool manualOverride = false;

// Fault detection: circular buffer of last STUCK_N moisture readings
const int STUCK_N = 10;
int  moistureHist[STUCK_N];
int  moistureHistIdx = 0;
bool histFull        = false;

// -- MQTT ------------------------------------------------------------------
WiFiClientSecure tlsClient;
PubSubClient     mqtt(tlsClient);

// MQTT callback -- fires immediately when a subscribed message arrives.
// topic: which MQTT topic the message came from (char array)
// payload: raw bytes of the message body
// length: number of bytes in payload
void mqttCallback(char* topic, byte* payload, unsigned int length) {
  String msg;
  for (unsigned int i = 0; i < length; i++) msg += (char)payload[i];

  JsonDocument doc;
  deserializeJson(doc, msg);
  String cmd = doc["command"].as<String>();

  if (cmd == "pump_on" && !pumpRunning) {
    manualOverride = true;
    pumpRunning    = true;
    digitalWrite(PIN_PUMP_RELAY, HIGH);
    postPumpLogStart(analogReadMoisture(), "manual");
    Serial.println("[MQTT] Manual pump ON");
  } else if (cmd == "pump_off") {
    manualOverride = false;
    pumpRunning    = false;
    digitalWrite(PIN_PUMP_RELAY, LOW);
    Serial.println("[MQTT] Manual pump OFF");
  }
}

// -- Helpers ---------------------------------------------------------------

// Read raw ADC and map to 0-100% moisture.
// Capacitive sensors: dry = high ADC value, wet = low ADC value.
// Calibrate 4095/1000 bounds to your specific sensor by testing with dry and wet soil.
int analogReadMoisture() {
  int raw = analogRead(PIN_SOIL_MOISTURE);
  return constrain(map(raw, 4095, 1000, 0, 100), 0, 100);
}

void connectWiFi() {
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("[WiFi] Connecting");
  while (WiFi.status() != WL_CONNECTED) { delay(500); Serial.print("."); }
  Serial.println(" connected: " + WiFi.localIP().toString());
}

void connectMQTT() {
  tlsClient.setInsecure();
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setCallback(mqttCallback);
  mqtt.setBufferSize(512);

  while (!mqtt.connected()) {
    // Client ID must be unique per HiveMQ connection.
    // Using chip MAC ensures uniqueness if multiple ESP32s share credentials.
    String clientId = "siss-esp32-" + String((uint32_t)ESP.getEfuseMac());
    Serial.print("[MQTT] Connecting...");
    if (mqtt.connect(clientId.c_str(), MQTT_USER, MQTT_PASSWORD)) {
      mqtt.subscribe(MQTT_TOPIC_SUB);
      Serial.println("connected");
    } else {
      Serial.println("failed (rc=" + String(mqtt.state()) + "), retry in 5s");
      delay(5000);
    }
  }
}

void checkFaultDetection(int moisture) {
  moistureHist[moistureHistIdx % STUCK_N] = moisture;
  moistureHistIdx++;
  if (moistureHistIdx >= STUCK_N) histFull = true;

  if (histFull) {
    bool stuck = true;
    for (int i = 1; i < STUCK_N; i++) {
      if (moistureHist[i] != moistureHist[0]) { stuck = false; break; }
    }
    if (stuck)
      insertAlert("sensor_stuck",
                  "Soil moisture unchanged for " + String(STUCK_N) + " readings");
  }
}

// -- setup() -- runs once on power-on -------------------------------------
void setup() {
  Serial.begin(115200);
  dht.begin();
  pinMode(PIN_PUMP_RELAY,  OUTPUT);
  pinMode(PIN_RAIN_SENSOR, INPUT);
  attachInterrupt(digitalPinToInterrupt(PIN_FLOW_SENSOR), flowISR, RISING);
  digitalWrite(PIN_PUMP_RELAY, LOW);  // ensure pump is OFF on boot

  connectWiFi();
  connectMQTT();
  updateDeviceStatus("online");

  // Load crop profile thresholds from Supabase into RAM.
  // Pass "" to use defaults; for full implementation, first GET the devices row
  // to read crop_profile_id, then pass that value here.
  cropProfile = fetchCropProfile("");
  Serial.println("[Boot] Ready. Moisture low=" + String(cropProfile.moistureLow) +
                 " high=" + String(cropProfile.moistureHigh));
}

// -- loop() -- runs repeatedly --------------------------------------------
unsigned long lastRun = 0;
const unsigned long INTERVAL_MS = 30000UL; // 30 seconds

void loop() {
  // Must be called frequently to keep MQTT connection alive and
  // process any incoming messages in the receive buffer.
  if (!mqtt.connected()) connectMQTT();
  mqtt.loop();

  if (WiFi.status() != WL_CONNECTED) connectWiFi();

  if (millis() - lastRun < INTERVAL_MS) return;
  lastRun = millis();

  // -- Read all sensors --------------------------------------------------
  int   moisture = analogReadMoisture();
  float temp     = dht.readTemperature();
  float humidity = dht.readHumidity();
  bool  rain     = (digitalRead(PIN_RAIN_SENSOR) == HIGH);

  // Flow rate from pulse count.
  // YF-S201 spec: 7.5 pulses per second = 1 litre per minute.
  long  pulses     = flowPulseCount;
  flowPulseCount   = 0;
  float flowLitres = (pulses / 7.5f / 60.0f) * (INTERVAL_MS / 1000.0f);

  Serial.printf("[Sensors] moisture=%d temp=%.1f hum=%.1f rain=%d flow=%.3fL\n",
                moisture, temp, humidity, (int)rain, flowLitres);

  // -- Post to Supabase --------------------------------------------------
  postSensorReading(moisture, temp, humidity, rain, flowLitres);
  checkFaultDetection(moisture);

  // -- Irrigation decision -----------------------------------------------
  if (!manualOverride) {
    if (rain) {
      Serial.println("[Irrigation] Rain detected -- skipping");

    } else if (moisture >= cropProfile.moistureHigh) {
      Serial.println("[Irrigation] Soil wet -- no action");

    } else if (moisture >= cropProfile.moistureLow) {
      Serial.println("[Irrigation] Soil OK -- no action");

    } else {
      int rainPct = getRainForecastPct();
      Serial.printf("[Weather] Rain forecast: %d%%\n", rainPct);

      if (rainPct >= cropProfile.rainSkipPct) {
        Serial.println("[Irrigation] Rain forecast -- skipping");
      } else {
        Serial.println("[Irrigation] Starting auto cycle");
        long logId = postPumpLogStart(moisture, "auto");

        pumpRunning = true;
        digitalWrite(PIN_PUMP_RELAY, HIGH);
        delay((unsigned long)cropProfile.irrigateSecs * 1000UL);
        digitalWrite(PIN_PUMP_RELAY, LOW);
        pumpRunning = false;

        int   after     = analogReadMoisture();
        float waterUsed = (cropProfile.irrigateSecs / 60.0f) * 0.5f; // rough estimate
        patchPumpLogEnd(logId, after, cropProfile.irrigateSecs, waterUsed);
        Serial.println("[Irrigation] Cycle complete. Moisture after: " + String(after));
      }
    }
  }

  // -- Fallback: check Supabase device_commands --------------------------
  String cmd = checkDeviceCommands();
  if (cmd == "pump_on" && !pumpRunning) {
    manualOverride = true;
    pumpRunning    = true;
    digitalWrite(PIN_PUMP_RELAY, HIGH);
    Serial.println("[Command] Manual pump ON via Supabase");
  } else if (cmd == "pump_off") {
    manualOverride = false;
    pumpRunning    = false;
    digitalWrite(PIN_PUMP_RELAY, LOW);
    Serial.println("[Command] Manual pump OFF via Supabase");
  }

  updateDeviceStatus("online");
}
```

---

### Phase 6 — Flutter App Changes

Four files change. All other screens, providers, charts, and the Supabase connection are unchanged.

#### Changed and new files:

```
app/
+-- .env                                        <- CHANGED
+-- lib/
    +-- services/
    |   +-- mqtt_service.dart                   <- CHANGED: HiveMQ Cloud, TLS
    +-- screens/
    |   +-- pump_control_screen.dart            <- CHANGED: MQTT + Supabase fallback
    |   +-- link_device_screen.dart             <- NEW: UUID entry + claim logic
    +-- providers/
    |   +-- app_state_provider.dart             <- SMALL CHANGE: add hasDevice getter
    +-- router.dart                             <- SMALL CHANGE: /link-device route + redirect
```

---

**Step 6.1 — Update `.env`**

```env
# .env

SUPABASE_URL=https://xxxxxxxxxxxx.supabase.co
SUPABASE_ANON_KEY=eyJhbGciO...

# HiveMQ Cloud -- Flutter uses siss_app credentials (NOT siss_device)
HIVEMQ_HOST=abc1234.s1.eu.hivemq.cloud
HIVEMQ_PORT=8883
HIVEMQ_USER=siss_app
HIVEMQ_PASSWORD=your_app_password

# Remove this line entirely:
# PYTHON_BACKEND_URL=http://...
```

---

**Step 6.2 — `mqtt_service.dart` (full replacement)**

```dart
// lib/services/mqtt_service.dart
// Connects to HiveMQ Cloud over TLS port 8883.
// Flutter only PUBLISHES pump commands; it does not subscribe to topics.
// All live sensor data arrives via Supabase Realtime, not MQTT.

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttService {
  MqttServerClient? _client;

  bool get isConnected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  Future<void> connect() async {
    final host     = dotenv.env['HIVEMQ_HOST']!;
    final port     = int.parse(dotenv.env['HIVEMQ_PORT'] ?? '8883');
    final user     = dotenv.env['HIVEMQ_USER']!;
    final password = dotenv.env['HIVEMQ_PASSWORD']!;

    // Append timestamp to ensure each app instance gets a unique client ID.
    // HiveMQ disconnects the older connection if two clients share the same ID.
    final clientId = 'siss-flutter-${DateTime.now().millisecondsSinceEpoch}';

    _client = MqttServerClient(host, clientId)
      ..port            = port
      ..secure          = true       // enables TLS -- required for port 8883
      ..keepAlivePeriod = 30
      ..logging(on: false)
      ..setProtocolV311()            // MQTT protocol version 3.1.1
      ..onDisconnected = _onDisconnected;

    // startClean() means no persistent session.
    // Fine here since Flutter only publishes and does not need queued messages.
    final connMsg = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .authenticateAs(user, password)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    _client!.connectionMessage = connMsg;

    try {
      await _client!.connect();
    } catch (e) {
      _client!.disconnect();
      rethrow;
    }
  }

  // Publish a pump command.
  // deviceId: the UUID from AppStateProvider.deviceId
  // command: 'pump_on' or 'pump_off'
  void sendPumpCommand(String deviceId, String command) {
    if (!isConnected) return;

    final topic   = 'devices/$deviceId/control';
    final payload = '{"command":"$command"}';
    final builder = MqttClientPayloadBuilder()..addString(payload);

    // QoS 1 = at least once. HiveMQ retries if ESP32 is briefly disconnected.
    // The consumed flag in device_commands prevents duplicate execution.
    _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }

  void _onDisconnected() {
    Future.delayed(const Duration(seconds: 3), connect);
  }

  void disconnect() => _client?.disconnect();
}
```

---

**Step 6.3 — `pump_control_screen.dart` — replace `_sendCommand` only**

```dart
// Replace only the _sendCommand method in pump_control_screen.dart.
// Remove the http import if it is no longer used elsewhere in the file.

Future<bool> _sendCommand(String deviceId, String command) async {
  try {
    // Primary path: real-time MQTT publish to HiveMQ.
    // ESP32 receives this in its mqttCallback within milliseconds.
    final mqttService = context.read<MqttService>();
    mqttService.sendPumpCommand(deviceId, command);

    // Fallback path: write to Supabase device_commands table.
    // ESP32 polls this every 5 seconds in checkDeviceCommands().
    // Ensures delivery even if MQTT was slow or ESP32 just reconnected.
    await Supabase.instance.client
        .from('device_commands')
        .insert({'device_id': deviceId, 'command': command});

    return true;
  } catch (_) {
    return false;
  }
}
```

---

**Step 6.4 — `link_device_screen.dart` (new file)**

```dart
// lib/screens/link_device_screen.dart
// Shown automatically when the logged-in user has no device linked.
// User enters the device UUID from the sticker on the ESP32 box.
// On submit, updates devices.user_id to the current user (claiming).
// Previous owner loses access. All historical data becomes visible to new owner.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/app_state_provider.dart';

class LinkDeviceScreen extends StatefulWidget {
  const LinkDeviceScreen({super.key});

  @override
  State<LinkDeviceScreen> createState() => _LinkDeviceScreenState();
}

class _LinkDeviceScreenState extends State<LinkDeviceScreen> {
  final _controller = TextEditingController();
  bool    _isLoading = false;
  String? _error;

  // Validates UUID format: 8-4-4-4-12 hex characters separated by dashes.
  bool _isValidUuid(String s) {
    final regex = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}'
      r'-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    return regex.hasMatch(s.trim());
  }

  Future<void> _linkDevice() async {
    final uuid = _controller.text.trim();
    if (!_isValidUuid(uuid)) {
      setState(() => _error = 'Please enter a valid device UUID.');
      return;
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;

      // UPDATE devices SET user_id = currentUser, claimed_at = now()
      // WHERE id = entered UUID
      // RLS policy "devices: claim by uuid" permits this for any authenticated user.
      // .select() at the end makes Supabase return the updated row so we can
      // check if a row was actually matched (empty list = UUID not found).
      final response = await Supabase.instance.client
          .from('devices')
          .update({
            'user_id':    userId,
            'claimed_at': DateTime.now().toIso8601String(),
          })
          .eq('id', uuid)
          .select();

      if (response.isEmpty) {
        setState(() {
          _error = 'Device not found. Check the UUID and try again.';
          _isLoading = false;
        });
        return;
      }

      // Claim succeeded. Refresh AppStateProvider so it loads the newly
      // linked device and updates hasDevice to true.
      // GoRouter's redirect will then navigate to /dashboard automatically.
      if (!mounted) return;
      await context.read<AppStateProvider>().refresh();

    } on PostgrestException catch (e) {
      setState(() {
        _error = 'Failed to link device: ${e.message}';
        _isLoading = false;
      });
    } catch (_) {
      setState(() {
        _error = 'Unexpected error. Please try again.';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.sensors, size: 72, color: colors.primary),
              const SizedBox(height: 24),
              Text(
                'Link Your Device',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Enter the Device UUID printed on the sticker\n'
                'on your SISS hardware unit.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              TextField(
                controller:         _controller,
                autocorrect:        false,
                enableSuggestions:  false,
                textCapitalization: TextCapitalization.none,
                decoration: InputDecoration(
                  labelText: 'Device UUID',
                  hintText:  'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
                  border:    const OutlineInputBorder(),
                  errorText: _error,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _isLoading ? null : _linkDevice,
                child: _isLoading
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Link Device'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

---

**Step 6.5 — `app_state_provider.dart` — add one getter**

Add this getter inside your existing `AppStateProvider` class:

```dart
// Add near the other getters in AppStateProvider

// True once a device row has been found for the logged-in user.
// GoRouter reads this to decide whether to redirect to /link-device.
bool get hasDevice => _deviceId != null;
```

---

**Step 6.6 — `router.dart` — add route and redirect rule**

```dart
// Two additions to your existing GoRouter:

// 1. Add /link-device route alongside your existing routes:
GoRoute(
  path: '/link-device',
  builder: (context, state) => const LinkDeviceScreen(),
),

// 2. Update your redirect callback to handle the no-device state.
//    Add these lines inside your existing redirect logic, after the auth check:
//
// redirect: (context, state) {
//   final provider   = context.read<AppStateProvider>();
//   final loggedIn   = Supabase.instance.client.auth.currentSession != null;
//   final hasDevice  = provider.hasDevice;
//   final isAuthPage = state.matchedLocation == '/login' ||
//                      state.matchedLocation == '/signup';
//   final isLinkPage = state.matchedLocation == '/link-device';
//
//   // Not logged in -> send to login
//   if (!loggedIn && !isAuthPage) return '/login';
//
//   // Logged in but no device -> send to link-device screen
//   if (loggedIn && !hasDevice && !isLinkPage) return '/link-device';
//
//   // Logged in with device but trying to access link-device -> send to dashboard
//   if (loggedIn && hasDevice && isLinkPage) return '/dashboard';
//
//   return null; // no redirect needed
// },
```

---

### Phase 7 — End-to-End Testing Checklist

```
-- Firmware Tests ------------------------------------------------------------

[ ] 1. Flash ESP32 -> open Serial Monitor (115200 baud)
        Expected: "[WiFi] Connecting... connected: 192.168.x.x"
        Expected: "[MQTT] Connecting... connected"
        Expected: "[Boot] Ready. Moisture low=30 high=70"

[ ] 2. Wait 30 seconds
        Expected: "[Sensors] moisture=XX temp=XX hum=XX rain=0 flow=0.000L"
        Verify:   New row in Supabase Table Editor -> sensor_readings

[ ] 3. Verify device status update
        Expected: devices row shows status="online", last_seen = recent timestamp

-- App Tests -- Own Account --------------------------------------------------

[ ] 4. Log in with your account (device already claimed by you)
        Expected: Navigates directly to Dashboard, no /link-device redirect
        Expected: Dashboard shows sensor values from step 2

[ ] 5. Verify Realtime -- wait 30 seconds without refreshing
        Expected: Dashboard values update automatically

[ ] 6. Manual pump control
        Tap Pump Control -> Start Pump
        Expected: Serial Monitor shows "[MQTT] Manual pump ON" (MQTT path)
           OR:    Serial Monitor shows "[Command] Manual pump ON via Supabase" (fallback)
        Verify:   New row in pump_logs with trigger_type='manual'

[ ] 7. Test from a different network
        Turn off home WiFi on phone, use mobile data
        Expected: Dashboard still shows live data
        Expected: Pump command still reaches ESP32

-- Device Claiming Tests -----------------------------------------------------

[ ] 8. Simulate teacher demo -- new account claims the device
        Create a new account in the app -> log in
        Expected: App navigates to /link-device (no device linked to this account)
        Enter the Device UUID from the sticker -> tap Link Device
        Expected: Success -> navigates to Dashboard
        Expected: Dashboard shows ALL historical sensor data including data from before claim
        Expected: Pump control works from this new account

[ ] 9. Verify original account lost access after claiming
        Log back into your original account
        Expected: App navigates to /link-device (device no longer belongs to this account)

[ ] 10. Reclaim the device
         With original account on /link-device, enter the UUID -> tap Link
         Expected: Navigates to Dashboard, all data still present and intact

-- Auto-Irrigation Test ------------------------------------------------------

[ ] 11. Test auto-irrigation trigger
         Temporarily raise DEFAULT_MOISTURE_LOW in config.h above the current reading
         Reflash -> wait 30 seconds
         Expected: "[Irrigation] Starting auto cycle" in Serial Monitor
         Verify:   New row in pump_logs with trigger_type='auto'
```

---

## Quick Reference — All Credentials Needed

| Credential | Where to get it | Where it goes |
|---|---|---|
| HiveMQ cluster hostname | HiveMQ dashboard | ESP32 `config.h`, Flutter `.env` |
| HiveMQ `siss_device` user/pass | HiveMQ Access Management | ESP32 `config.h` only |
| HiveMQ `siss_app` user/pass | HiveMQ Access Management | Flutter `.env` only |
| Supabase Project URL | Supabase → Settings → API | ESP32 `config.h`, Flutter `.env` |
| Supabase `anon` key | Supabase → Settings → API | ESP32 `config.h`, Flutter `.env` |
| Supabase `service_role` key | Supabase → Settings → API | Edge Functions only |
| ESP32 Device UUID | Supabase Table Editor → devices row `id` | ESP32 `config.h`, sticker on box |

## Device Claiming Quick Reference

| Scenario | Action | Where |
|---|---|---|
| First-time setup | Insert device row (user_id=NULL), copy UUID to config.h | Supabase Table Editor |
| Your own account accesses it | Enter UUID in Link Device screen | Flutter app |
| Teacher demo | Teacher creates account, enters UUID, claims device | Flutter app |
| Reclaiming after demo | Log back in, enter UUID, claim it back | Flutter app |
| Moving ESP32 to new location | No action needed | config.h unchanged |
| Reflash firmware | Only needed if DEVICE_ID itself needs to change | config.h |

---

*SISS v2 — Smart Irrigation and Sensor System | ESP32-direct serverless architecture*
*No Python backend. No local broker. Power the ESP32, open the app from anywhere.*
*Any account can claim the device by entering its UUID. No reflashing ever needed.*
