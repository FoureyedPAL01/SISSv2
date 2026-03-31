# PWM Pump Control Implementation

## Overview

This document describes the implementation of PWM (Pulse Width Modulation) pump control for SISSv2, replacing the previous relay-based ON/OFF control with variable speed control using a D4184 MOSFET module.

## Changes Summary

### Hardware Requirements
- **Previous**: Relay module (GPIO HIGH/LOW)
- **New**: D4184 MOSFET module with PWM input
- **ESP32 GPIO**: PIN_PUMP_PWM (26) outputs PWM signal to MOSFET

---

## 1. Database Changes

### SQL Migration
File: `docs/sql/005_pwm_duty_support.sql`

```sql
ALTER TABLE crop_profiles ADD COLUMN IF NOT EXISTS pwm_duty int DEFAULT 200;
```

- **Column**: `pwm_duty`
- **Type**: Integer (0-255)
- **Default**: 200 (~78% duty cycle)
- **Description**: PWM duty cycle for pump speed control per crop profile

---

## 2. ESP32 Firmware Changes

### 2.1 config.h
Added PWM-related settings:

```cpp
// -- PWM Pump (D4184 MOSFET) -----------------------------------------------
#define PIN_PUMP_PWM       26  // GPIO26 - PWM output to D4184 MOSFET
#define DEFAULT_PWM_DUTY   200 // Default PWM duty cycle (0-255), ~78%
```

### 2.2 supabase_client.h
Updated CropProfile struct:

```cpp
struct CropProfile {
  int moistureLow;
  int irrigateSecs;
  int rainSkipPct;
  int pwmDuty;  // PWM duty cycle (0-255), defaults to 200 (~78%)
};
```

Updated `fetchCropProfile()` to retrieve `pwm_duty` from database.

### 2.3 esp32.ino (Full Rewrite)

**Key Changes:**
- Replaced `digitalWrite()` with `analogWrite(PIN_PUMP_PWM, duty)`
- Added PWM command parsing from MQTT:
  ```json
  {"command":"pump_on"}                    // Uses default PWM (200)
  {"command":"pump_on", "pwm":150}         // Custom PWM (0-255)
  {"command":"set_pwm", "value":200}       // Set PWM without pump state
  {"command":"pump_off"}                   // analogWrite(0)
  ```
- Water usage calculation adjusted for PWM: `waterUsed * (pwmDuty / 255)`
- Auto-irrigation uses PWM from crop profile

---

## 3. Flutter App Changes

### 3.1 mqtt_service.dart
Added optional PWM parameter:

```dart
void sendPumpCommand(String deviceId, String command, {int? pwmValue}) {
  // ...
  payload = '{"command":"$command","pwm":$pwmValue}';
}
```

### 3.2 dashboard_screen.dart
- Added `_pwmValue` state variable (default: 200)
- Added PWM slider (0-100%) in pump card
- Updated `_sendCommand()` to include PWM value:
  ```dart
  _sendCommand(deviceId, 'pump_on', pwm: _pwmValue)
  ```

**UI Layout:**
```
┌─────────────────────────────────────┐
│  PUMP                      [ON/OFF]│
│                                     │
│  Speed: ━━━━━━━━●━━━━━━━━━ 78%     │
│  PWM: 200                          │
└─────────────────────────────────────┘
```

### 3.3 crop_profiles_screen.dart
- Added `_pwmDuty` state variable
- Added PWM duty slider (0-255) in profile editor
- Saves `pwm_duty` to database on profile save

---

## 4. MQTT Command Format

### Commands from Flutter to ESP32

| Command | Payload | Description |
|---------|---------|-------------|
| Start Pump (default) | `{"command":"pump_on"}` | Use DEFAULT_PWM_DUTY (200) |
| Start Pump (custom) | `{"command":"pump_on","pwm":150}` | Use custom PWM value |
| Set PWM only | `{"command":"set_pwm","value":200}` | Change PWM without pump state |
| Stop Pump | `{"command":"pump_off"}` | Set PWM to 0 (off) |

---

## 5. Data Flow

```
User adjusts slider → Set PWM value
        │
        ▼
   Tap "START"
        │
        ▼
   MQTT: {"command":"pump_on","pwm":150}
        │
        ▼
   HiveMQ Cloud
        │
        ▼
   ESP32 mqttCallback() → Parse JSON
        │
        ▼
   analogWrite(PIN_PWM, pwmValue)
        │
        ▼
   D4184 MOSFET → Pump at variable speed
        │
        ▼
   Timer runs (max 2 min) → auto-stop
```

---

## 6. Backward Compatibility

- **Default PWM = 200 (~78%)** - Closest to previous relay ON behavior
- **Legacy commands work** - `{"command":"pump_on"}` uses DEFAULT_PWM_DUTY
- **Relay mode** - Set PWM to 255 (full) for relay equivalent, 0 for OFF

---

## 7. Testing Checklist

- [ ] PWM slider at 0% → Pump OFF
- [ ] PWM slider at 50% → Pump runs at ~50% speed
- [ ] PWM slider at 100% → Pump runs at full speed
- [ ] MQTT with `"pwm":255` → Full speed
- [ ] Auto-irrigation uses profile PWM setting
- [ ] Water usage display shows correct values (adjusted for PWM)
- [ ] Safety timeout (2 min) still works with PWM

---

## 8. Files Modified

| File | Change |
|------|--------|
| `docs/sql/005_pwm_duty_support.sql` | New SQL migration |
| `esp32/config.h` | Added PWM settings |
| `esp32/supabase_client.h` | Added pwmDuty to CropProfile |
| `esp32/esp32.ino` | Full rewrite for PWM control |
| `app/lib/services/mqtt_service.dart` | Added pwmValue parameter |
| `app/lib/screens/dashboard_screen.dart` | Added PWM slider UI |
| `app/lib/screens/crop_profiles_screen.dart` | Added PWM profile setting |

---

## 9. Usage Instructions

### Setting PWM from Dashboard
1. Adjust the Speed slider (0-100%)
2. Tap "START" to start pump at selected speed
3. Tap again to stop

### Setting PWM per Crop Profile
1. Go to Crop Profiles screen
2. Create/edit a profile
3. Set "Pump Speed (PWM)" slider
4. Save profile

### Auto-Irrigation
- Uses PWM value from active crop profile
- If not set, defaults to 200 (~78%)

---

## 10. Sensor Calibration (Required)

**Before first use**, sensors must be calibrated to ensure accurate readings.

### Issues Fixed
| Issue | Symptom | Fix |
|-------|---------|-----|
| Moisture reads high in air | Shows ~21% when dry | Updated calibration constants |
| Rain sensor always HIGH | Shows rain=1 when dry | Added `RAIN_SENSOR_INVERT` config |

### Calibration Settings in config.h

```cpp
// Soil Moisture - update with YOUR sensor readings
#define MOISTURE_AIR_RAW    3200  // ADC reading in dry air (0%)
#define MOISTURE_WATER_RAW  1100  // ADC reading in water (100%)

// Rain Sensor - set based on your sensor type
#define RAIN_SENSOR_INVERT  false // Active LOW (most YL-38 modules)

// Calibration Mode - set true to print raw values
#define CALIBRATION_MODE    true  // Set false after calibration
```

### Calibration Procedure
1. Set `CALIBRATION_MODE = true` in config.h
2. Flash firmware
3. Open Serial Monitor at 115200 baud
4. Note raw values for moisture (in air and water)
5. Test rain sensor with water drop
6. Update config.h with measured values
7. Set `CALIBRATION_MODE = false`
8. Reflash firmware

### Quick Reference
- Moisture: `map(raw, AIR_RAW, WATER_RAW, 0, 100)`
- Rain: Active LOW → `RAIN_SENSOR_INVERT = false`

For detailed calibration guide, see `docs/Sensor_Calibration_Guide.md`

---

*Last updated: 2026-03-30*