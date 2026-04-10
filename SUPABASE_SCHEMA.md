# SISSv2 Supabase Schema Documentation

Generated on: 2026-04-09  
Last verified against live Supabase metadata: 2026-04-09 15:47:16 +05:30  
Project URL: `https://tbvacoyjjjyrwrtzasps.supabase.co`

## Database Overview

- Scope: `public` schema
- Total documented tables: 10
- RLS enabled: 10/10 tables
- Migration history source: `supabase.list_migrations` (no rows returned)

| Table | Rows (sample count) | RLS |
|---|---:|---|
| `public.users` | 1 | enabled |
| `public.devices` | 1 | enabled |
| `public.sensor_readings` | 2830 | enabled |
| `public.pump_logs` | 58 | enabled |
| `public.crop_profiles` | 3 | enabled |
| `public.alerts` | 10 | enabled |
| `public.fertigation_logs` | 3 | enabled |
| `public.device_commands` | 37 | enabled |
| `public.device_tokens` | 1 | enabled |
| `public.user_profiles` | 1 | enabled |

## Entity Relationship Diagram (Text)

```text
auth.users
  |--(1:1 via id)-> public.users
  |--(1:1 via user_id unique)-> public.user_profiles
  \--(1:1 via user_id PK)-> public.device_tokens

public.users
  |--(1:N)-> public.devices (devices.user_id)
  \--(1:N)-> public.crop_profiles (crop_profiles.user_id)

public.crop_profiles
  |--(1:N)-> public.devices (devices.crop_profile_id)
  \--(1:N)-> public.fertigation_logs (fertigation_logs.crop_profile_id)

public.devices
  |--(1:N)-> public.sensor_readings
  |--(1:N)-> public.pump_logs
  |--(1:N)-> public.alerts
  |--(1:N)-> public.device_commands
  \--(1:N)-> public.fertigation_logs
```

---

## Table: `public.users`

Purpose: canonical app-level user settings/preferences row mapped to `auth.users`.

- Primary key: `id`
- Sample data count: 1
- Foreign keys:
  - `users.id -> auth.users.id` (`ON DELETE CASCADE`)
- Indexes:
  - `users_pkey` (unique btree on `id`)
- RLS policies:
  - `users: own row` (`ALL`, role `public`, `auth.uid() = id`)

| Column | Type | Nullable | Default | Constraints |
|---|---|---|---|---|
| `id` | `uuid` | no |  | `PK`, `FK -> auth.users.id` |
| `username` | `text` | yes |  |  |
| `email` | `text` | yes |  |  |
| `created_at` | `timestamptz` | yes | `now()` |  |
| `temp_unit` | `text` | yes | `'celsius'::text` |  |
| `volume_unit` | `text` | yes | `'litres'::text` |  |
| `timezone` | `text` | yes | `'UTC'::text` |  |
| `pump_alerts` | `boolean` | yes | `true` |  |
| `soil_moisture_alerts` | `boolean` | yes | `true` |  |
| `weather_alerts` | `boolean` | yes | `true` |  |
| `fertigation_reminders` | `boolean` | yes | `true` |  |
| `device_offline_alerts` | `boolean` | yes | `true` |  |
| `weekly_summary` | `boolean` | yes | `false` |  |
| `location_lat` | `text` | yes | `'19.0760'::text` |  |
| `location_lon` | `text` | yes | `'72.8777'::text` |  |
| `wind_unit` | `text` | yes | `'km/h'::text` |  |
| `precipitation_unit` | `text` | yes | `'mm'::text` |  |
| `aqi_type` | `text` | yes | `'us'::text` |  |

## Table: `public.devices`

Purpose: registered device inventory, ownership, and high-level state.

- Primary key: `id`
- Sample data count: 1
- Foreign keys:
  - `devices.user_id -> users.id` (`ON DELETE SET NULL`)
  - `devices.crop_profile_id -> crop_profiles.id` (`ON DELETE SET NULL`)
- Indexes:
  - `devices_pkey` (unique btree on `id`)
- RLS policies:
  - `anon_insert_devices` (`INSERT`, role `anon`, `WITH CHECK true`)
  - `anon_select_devices` (`SELECT`, role `anon`, `USING true`)
  - `anon_update_devices` (`UPDATE`, role `anon`, `USING true`, `WITH CHECK true`)
  - `devices: claim by uuid` (`UPDATE`, role `public`, `USING auth.uid() IS NOT NULL`, `WITH CHECK auth.uid() = user_id`)
  - `devices: esp32 status update` (`UPDATE`, role `public`, `USING true`)
  - `devices: owner reads` (`SELECT`, role `public`, `USING auth.uid() = user_id`)

| Column | Type | Nullable | Default | Constraints |
|---|---|---|---|---|
| `id` | `uuid` | no | `gen_random_uuid()` | `PK` |
| `user_id` | `uuid` | yes |  | `FK -> users.id` |
| `name` | `text` | yes | `'My Plant'::text` |  |
| `status` | `text` | yes | `'offline'::text` |  |
| `last_seen` | `timestamptz` | yes |  |  |
| `crop_profile_id` | `bigint` | yes |  | `FK -> crop_profiles.id` |
| `claimed_at` | `timestamptz` | yes |  |  |
| `created_at` | `timestamptz` | yes | `now()` |  |

## Table: `public.sensor_readings`

Purpose: time-series telemetry from devices (soil, weather, flow).

- Primary key: `id`
- Sample data count: 2830
- Foreign keys:
  - `sensor_readings.device_id -> devices.id` (`ON DELETE CASCADE`)
- Indexes:
  - `sensor_readings_pkey` (unique btree on `id`)
- RLS policies:
  - `anon_insert_sensor_readings` (`INSERT`, role `anon`, `WITH CHECK true`)
  - `anon_select_sensor_readings` (`SELECT`, role `anon`, `USING true`)
  - `anon_update_sensor_readings` (`UPDATE`, role `anon`, `USING true`, `WITH CHECK true`)
  - `sensor_readings: esp32 insert` (`INSERT`, role `public`, `WITH CHECK device_id IN (SELECT devices.id FROM devices)`)
  - `sensor_readings: owner reads` (`SELECT`, role `public`, `USING device_id IN (SELECT devices.id FROM devices WHERE devices.user_id = auth.uid())`)

| Column | Type | Nullable | Default | Constraints |
|---|---|---|---|---|
| `id` | `bigint` | no | `nextval('sensor_readings_id_seq'::regclass)` | `PK` |
| `device_id` | `uuid` | yes |  | `FK -> devices.id` |
| `soil_moisture` | `integer` | yes |  |  |
| `temperature_c` | `numeric` | yes |  |  |
| `humidity` | `numeric` | yes |  |  |
| `rain_detected` | `boolean` | yes | `false` |  |
| `flow_litres` | `numeric` | yes |  |  |
| `recorded_at` | `timestamptz` | yes | `now()` |  |
| `created_at` | `timestamptz` | yes | `recorded_at` | generated column defaulting to `recorded_at` |

## Table: `public.pump_logs`

Purpose: irrigation run logs and water usage details.

- Primary key: `id`
- Sample data count: 58
- Foreign keys:
  - `pump_logs.device_id -> devices.id` (`ON DELETE CASCADE`)
- Indexes:
  - `pump_logs_pkey` (unique btree on `id`)
- RLS policies:
  - `anon_insert_pump_logs` (`INSERT`, role `anon`, `WITH CHECK true`)
  - `anon_select_pump_logs` (`SELECT`, role `anon`, `USING true`)
  - `anon_update_pump_logs` (`UPDATE`, role `anon`, `USING true`, `WITH CHECK true`)
  - `pump_logs: esp32 insert` (`INSERT`, role `public`, `WITH CHECK device_id IN (SELECT devices.id FROM devices)`)
  - `pump_logs: esp32 update` (`UPDATE`, role `public`, `USING device_id IN (SELECT devices.id FROM devices)`)
  - `pump_logs: owner reads` (`SELECT`, role `public`, `USING device_id IN (SELECT devices.id FROM devices WHERE devices.user_id = auth.uid())`)

| Column | Type | Nullable | Default | Constraints |
|---|---|---|---|---|
| `id` | `bigint` | no | `nextval('pump_logs_id_seq'::regclass)` | `PK` |
| `device_id` | `uuid` | yes |  | `FK -> devices.id` |
| `pump_on_at` | `timestamptz` | yes | `now()` |  |
| `duration_seconds` | `integer` | yes |  |  |
| `water_used_litres` | `numeric` | yes |  |  |
| `moisture_before` | `integer` | yes |  |  |
| `moisture_after` | `integer` | yes |  |  |
| `rain_detected` | `boolean` | yes | `false` |  |
| `trigger_type` | `text` | yes | `'auto'::text` |  |
| `created_at` | `timestamptz` | yes | `now()` |  |

## Table: `public.crop_profiles`

Purpose: per-user crop/plant irrigation configuration and cached plant metadata.

- Primary key: `id`
- Sample data count: 3
- Foreign keys:
  - `crop_profiles.user_id -> users.id` (`ON DELETE CASCADE`)
- Referenced by:
  - `devices.crop_profile_id`
  - `fertigation_logs.crop_profile_id`
- Indexes:
  - `crop_profiles_pkey` (unique btree on `id`)
- RLS policies:
  - `crop_profiles: esp32 read` (`SELECT`, role `public`, `USING true`)
  - `crop_profiles: owner manages` (`ALL`, role `public`, `USING auth.uid() = user_id`)

| Column | Type | Nullable | Default | Constraints |
|---|---|---|---|---|
| `id` | `bigint` | no | `nextval('crop_profiles_id_seq'::regclass)` | `PK` |
| `user_id` | `uuid` | yes |  | `FK -> users.id` |
| `name` | `text` | no |  |  |
| `moisture_threshold_low` | `integer` | yes | `30` |  |
| `moisture_threshold_high` | `integer` | yes | `70` |  |
| `irrigation_duration_s` | `integer` | yes | `60` |  |
| `weather_sensitivity` | `integer` | yes | `60` |  |
| `created_at` | `timestamptz` | yes | `now()` |  |
| `plant_name` | `text` | yes |  |  |
| `min_moisture` | `numeric` | yes | `30` |  |
| `perenual_species_id` | `integer` | yes |  |  |
| `perenual_data` | `jsonb` | yes |  |  |
| `perenual_cached_at` | `timestamptz` | yes |  |  |
| `perenual_care_data` | `jsonb` | yes |  |  |
| `pwm_duty` | `integer` | yes | `200` |  |

## Table: `public.alerts`

Purpose: generated device alerts and resolution state.

- Primary key: `id`
- Sample data count: 10
- Foreign keys:
  - `alerts.device_id -> devices.id` (`ON DELETE CASCADE`)
- Indexes:
  - `alerts_pkey` (unique btree on `id`)
- RLS policies:
  - `alerts: esp32 insert` (`INSERT`, role `public`, `WITH CHECK device_id IN (SELECT devices.id FROM devices)`)
  - `alerts: owner delete` (`DELETE`, role `public`, `USING device_id IN (SELECT devices.id FROM devices WHERE devices.user_id = auth.uid())`)
  - `alerts: owner reads` (`SELECT`, role `public`, `USING device_id IN (SELECT devices.id FROM devices WHERE devices.user_id = auth.uid())`)
  - `alerts: owner update` (`UPDATE`, role `public`, `USING device_id IN (SELECT devices.id FROM devices WHERE devices.user_id = auth.uid())`)
  - `anon_insert_alerts` (`INSERT`, role `anon`, `WITH CHECK true`)
  - `anon_select_alerts` (`SELECT`, role `anon`, `USING true`)

| Column | Type | Nullable | Default | Constraints |
|---|---|---|---|---|
| `id` | `bigint` | no | `nextval('alerts_id_seq'::regclass)` | `PK` |
| `device_id` | `uuid` | yes |  | `FK -> devices.id` |
| `alert_type` | `text` | yes |  |  |
| `message` | `text` | yes |  |  |
| `resolved` | `boolean` | yes | `false` |  |
| `created_at` | `timestamptz` | yes | `now()` |  |

## Table: `public.fertigation_logs`

Purpose: fertilization events associated with device and optional crop profile.

- Primary key: `id`
- Sample data count: 3
- Foreign keys:
  - `fertigation_logs.device_id -> devices.id` (`ON DELETE CASCADE`)
  - `fertigation_logs.crop_profile_id -> crop_profiles.id` (`ON DELETE SET NULL`)
- Indexes:
  - `fertigation_logs_pkey` (unique btree on `id`)
- RLS policies:
  - `fertigation_logs: owner manages` (`ALL`, role `public`, `USING device_id IN (SELECT devices.id FROM devices WHERE devices.user_id = auth.uid())`)

| Column | Type | Nullable | Default | Constraints |
|---|---|---|---|---|
| `id` | `bigint` | no | `nextval('fertigation_logs_id_seq'::regclass)` | `PK` |
| `device_id` | `uuid` | yes |  | `FK -> devices.id` |
| `crop_profile_id` | `bigint` | yes |  | `FK -> crop_profiles.id` |
| `fertilized_at` | `timestamptz` | yes | `now()` |  |
| `notes` | `text` | yes |  |  |

## Table: `public.device_commands`

Purpose: command queue from app to devices, with consumed state.

- Primary key: `id`
- Sample data count: 37
- Foreign keys:
  - `device_commands.device_id -> devices.id` (`ON DELETE CASCADE`)
- Indexes:
  - `device_commands_pkey` (unique btree on `id`)
- RLS policies:
  - `anon_insert_device_commands` (`INSERT`, role `anon`, `WITH CHECK true`)
  - `anon_select_device_commands` (`SELECT`, role `anon`, `USING true`)
  - `anon_update_device_commands` (`UPDATE`, role `anon`, `USING true`, `WITH CHECK true`)
  - `device_commands: esp32 read` (`SELECT`, role `public`, `USING true`)
  - `device_commands: esp32 update` (`UPDATE`, role `public`, `USING device_id IN (SELECT devices.id FROM devices)`)
  - `device_commands: owner insert` (`INSERT`, role `public`, `WITH CHECK device_id IN (SELECT devices.id FROM devices WHERE devices.user_id = auth.uid())`)

| Column | Type | Nullable | Default | Constraints |
|---|---|---|---|---|
| `id` | `bigint` | no | `nextval('device_commands_id_seq'::regclass)` | `PK` |
| `device_id` | `uuid` | yes |  | `FK -> devices.id` |
| `command` | `text` | no |  |  |
| `consumed` | `boolean` | yes | `false` |  |
| `created_at` | `timestamptz` | yes | `now()` |  |

## Table: `public.device_tokens`

Purpose: user-level push token storage for notifications.

- Primary key: `user_id`
- Sample data count: 1
- Foreign keys:
  - `device_tokens.user_id -> auth.users.id` (`ON DELETE CASCADE`)
- Indexes:
  - `device_tokens_pkey` (unique btree on `user_id`)
- RLS policies:
  - `Users manage own token` (`ALL`, role `public`, `USING auth.uid() = user_id`, `WITH CHECK auth.uid() = user_id`)

| Column | Type | Nullable | Default | Constraints |
|---|---|---|---|---|
| `user_id` | `uuid` | no |  | `PK`, `FK -> auth.users.id` |
| `fcm_token` | `text` | no |  |  |
| `updated_at` | `timestamptz` | no | `now()` |  |

## Table: `public.user_profiles`

Purpose: normalized user profile and notification/settings data.

- Primary key: `id`
- Sample data count: 1
- Foreign keys:
  - `user_profiles.user_id -> auth.users.id` (`ON DELETE CASCADE`)
- Unique constraints:
  - `user_profiles_user_id_key` on `user_id`
- Indexes:
  - `user_profiles_pkey` (unique btree on `id`)
  - `user_profiles_user_id_key` (unique btree on `user_id`)
- RLS policies:
  - `Users can select own profile` (`SELECT`, role `public`, `USING auth.uid() = user_id`)
  - `Users can insert own profile` (`INSERT`, role `public`, `WITH CHECK auth.uid() = user_id`)
  - `Users can update own profile` (`UPDATE`, role `public`, `USING auth.uid() = user_id`)
  - `Users can delete own profile` (`DELETE`, role `public`, `USING auth.uid() = user_id`)

| Column | Type | Nullable | Default | Constraints |
|---|---|---|---|---|
| `id` | `uuid` | no | `gen_random_uuid()` | `PK` |
| `user_id` | `uuid` | no |  | `UNIQUE`, `FK -> auth.users.id` |
| `username` | `text` | yes |  |  |
| `temp_unit` | `text` | yes | `'celsius'::text` |  |
| `volume_unit` | `text` | yes | `'litres'::text` |  |
| `wind_unit` | `text` | yes | `'km/h'::text` |  |
| `precipitation_unit` | `text` | yes | `'mm'::text` |  |
| `aqi_type` | `text` | yes | `'us'::text` |  |
| `timezone` | `text` | yes | `'UTC'::text` |  |
| `location_lat` | `text` | yes | `'19.0760'::text` |  |
| `location_lon` | `text` | yes | `'72.8777'::text` |  |
| `pump_alerts` | `boolean` | yes | `true` |  |
| `soil_moisture_alerts` | `boolean` | yes | `true` |  |
| `weather_alerts` | `boolean` | yes | `true` |  |
| `fertigation_reminders` | `boolean` | yes | `true` |  |
| `device_offline_alerts` | `boolean` | yes | `true` |  |
| `weekly_summary` | `boolean` | yes | `false` |  |
| `created_at` | `timestamptz` | yes | `now()` |  |
| `updated_at` | `timestamptz` | yes | `now()` | updated by trigger |

---

## Triggers and Functions

### Triggers (relevant to this schema)

| Table | Trigger | Timing/Event | Function |
|---|---|---|---|
| `auth.users` | `on_auth_user_created` | `AFTER INSERT` | `public.handle_new_user()` |
| `public.alerts` | `alert_notifications` | `AFTER INSERT` | `supabase_functions.http_request(...)` |
| `public.user_profiles` | `update_user_profiles_updated_at` | `BEFORE UPDATE` | `public.update_updated_at()` |

Notes:
- `alert_notifications` trigger definition includes an embedded Bearer token in DB metadata; this documentation intentionally redacts token value.

### Public Functions

| Function | Return type | Language | Summary |
|---|---|---|---|
| `public.delete_old_commands()` | `void` | `plpgsql` | Deletes consumed `device_commands` older than 1 hour. |
| `public.handle_new_user()` | `trigger` | `plpgsql` | Inserts a row into `public.user_profiles` when a new `auth.users` row is created. |
| `public.update_updated_at()` | `trigger` | `plpgsql` | Sets `NEW.updated_at = NOW()` before row update. |

---

## Migration History

Result from Supabase migrations API:

- No migration records returned (`[]`).
- This usually means migrations were not tracked in this project, were reset, or are managed outside the connected metadata source.

---

## Schema Design Observations

1. Access model is permissive for device-side ingestion on several tables (`anon_*` policies with `true` checks). Confirm this is intentional for production.
2. `public.handle_new_user()` inserts `(user_id, email)` into `public.user_profiles`, but `user_profiles` currently has no `email` column. This function likely fails at runtime unless schema/function drift is addressed.
3. Most foreign keys on telemetry/event tables correctly enforce cascade delete from `devices`.
4. No non-PK performance indexes are present on high-volume tables (`sensor_readings`, `pump_logs`, `device_commands`) beyond primary keys; query-path indexing may need review if read volume grows.
