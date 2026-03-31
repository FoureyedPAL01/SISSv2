# Alert System Implementation

## Overview
The ESP32 now sends alerts to Supabase when specific irrigation events occur. A webhook in Supabase triggers the `send-alert-notification` Edge Function, which sends FCM push notifications to the user's phone.

## Alert Types

| Alert Type | Trigger | Cooldown | Classification |
|-----------|---------|----------|----------------|
| `pump_on` | Manual pump started via app | None | Warning |
| `pump_off` | Manual pump stopped via app | None | Warning |
| `pump_timeout` | 2-minute safety auto-stop | None | Warning |
| `rain_started` | Rain sensor detected moisture | None (edge) | Info |
| `rain_stopped` | Rain sensor cleared | None (edge) | Info |
| `soil_dry` | Moisture below threshold | 10 min | Info |
| `auto_irrigation_started` | Auto-irrigation begins | None | Info |
| `auto_irrigation_stopped` | Auto-irrigation ends | None | Info |

## Files Changed

### `esp32/config.h`
- Set `CALIBRATION_MODE` to `false`
- Added `ALERT_COOLDOWN_SOIL_MS` (600000UL = 10 min)

### `esp32/supabase_client.h`
- Added `postAlert(String alertType, String message)` function
- Inserts into `alerts` table with `device_id`, `alert_type`, `message`

### `esp32/esp32.ino`
- Added alert state variables: `lastSoilAlertMs`, `prevRain`
- Added `postAlert("pump_on", ...)` call in manual pump ON handler
- Added `postAlert("pump_off", ...)` call in manual pump OFF handler
- Added `postAlert("pump_timeout", ...)` call in safety timeout handler
- Added rain edge detection: `rain_started` (rising) and `rain_stopped` (falling)
- Added `soil_dry` alert with 10-minute cooldown (skips if pump running)
- Added `postAlert("auto_irrigation_started", ...)` at auto-irrigation start
- Added `postAlert("auto_irrigation_stopped", ...)` at auto-irrigation end

## Alert Flow
```
ESP32 detects condition
  → postAlert() inserts row into Supabase alerts table
  → Supabase webhook fires (configured in Dashboard)
  → send-alert-notification Edge Function executes
  → FCM push notification sent to user's phone
  → Alert appears in Flutter app alerts screen
```

## Supabase Schema: `alerts` table
```sql
CREATE TABLE alerts (
  id          bigserial PRIMARY KEY,
  device_id   uuid REFERENCES devices(id),
  alert_type  text,
  message     text,
  resolved    boolean DEFAULT false,
  created_at  timestamptz DEFAULT now()
);
```

## RLS Policies
- **INSERT**: Open for ESP32 via anon key (`anon_insert_alerts`, `alerts: esp32 insert`)
- **SELECT**: Owner reads only (`alerts: owner reads`) + anon fallback (`anon_select_alerts`)
- **UPDATE/DELETE**: Owner only (`alerts: owner update`, `alerts: owner delete`)
