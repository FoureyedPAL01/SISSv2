# RootSync — Smart Irrigation System

## Complete Technical Reference

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Hardware Architecture](#2-hardware-architecture)
3. [ESP32 Firmware](#3-esp32-firmware)
4. [Sensor Mathematics & Calibration](#4-sensor-mathematics--calibration)
5. [PWM Pump Control](#5-pwm-pump-control)
6. [Auto-Irrigation Decision Logic](#6-auto-irrigation-decision-logic)
7. [Supabase Database Schema](#7-supabase-database-schema)
8. [Flutter Mobile Application](#8-flutter-mobile-application)
9. [Data Flow Architecture](#9-data-flow-architecture)
10. [Communication Protocols](#10-communication-protocols)
11. [Efficiency Scoring](#11-efficiency-scoring)
12. [Edge Functions](#12-edge-functions)
13. [Security Model](#13-security-model)

---

## 1. System Overview

RootSync is a complete IoT-based smart irrigation system comprising four interconnected layers:

```
┌─────────────────────────────────────────────────────────────────────┐
│                        SYSTEM ARCHITECTURE                          │
│                                                                     │
│  ┌──────────┐    HTTPS/REST     ┌──────────────┐    WebSocket      │
│  │  ESP32   │ ─────────────────▶│   Supabase   │ ◀────────────────▶│
│  │ Firmware │ ◀─────────────────│   Backend    │    Flutter App    │
│  │          │    MQTT Commands  │              │                   │
│  └────┬─────┘                   └──────┬───────┘                   │
│       │                                │                           │
│       │  Open-Meteo API                │  Perenual API             │
│       │  (Weather Forecast)            │  (Plant Care Data)        │
│       ▼                                ▼                           │
│  ┌──────────┐                   ┌──────────────┐                   │
│  │ Sensors  │                   │  Edge        │                   │
│  │ & Pump   │                   │  Functions   │                   │
│  └──────────┘                   └──────────────┘                   │
└─────────────────────────────────────────────────────────────────────┘
```

| Layer | Technology | Purpose |
|-------|-----------|---------|
| Embedded | ESP32 + Arduino | Sensor reading, pump control, MQTT |
| Backend | Supabase (PostgreSQL) | Data storage, auth, realtime, edge functions |
| Mobile | Flutter (Dart) | User interface, monitoring, control |
| Cloud | HiveMQ + Open-Meteo + Perenual | Real-time messaging, weather, plant data |

---

## 2. Hardware Architecture

### 2.1 Component List

| Component | Model | GPIO Pin | Function |
|-----------|-------|----------|----------|
| Microcontroller | ESP32 DevKit V1 | — | Main processor |
| Temperature/Humidity | DHT11 | GPIO 4 | Ambient conditions |
| Soil Moisture | Capacitive (analog) | GPIO 34 | Soil water content |
| Rain Sensor | YL-38 (digital) | GPIO 35 | Precipitation detection |
| Flow Sensor | YF-S201 (pulse) | GPIO 18 | Water volume measurement |
| Pump Driver | D4184 MOSFET | GPIO 2 | Variable speed pump control |

### 2.2 Pin Mapping

```
┌──────────────────────────────────────────────────┐
│              ESP32 DevKit V1                     │
│                                                  │
│  GPIO 34 ───┐  Soil Moisture (Analog In)         │
│  GPIO 35 ───┤  Rain Sensor (Digital In)          │
│  GPIO 18 ───┤  Flow Sensor (Interrupt In)        │
│  GPIO 4  ───┤  DHT11 Data (Digital I/O)          │
│  GPIO 2  ───┤  PWM Pump Control (PWM Out)        │
│                                                  │
│  3.3V ──────┤  Sensor power                      │
│  GND  ──────┤  Common ground                     │
└──────────────────────────────────────────────────┘
```

### 2.3 Signal Characteristics

| Sensor | Signal Type | Range | Resolution |
|--------|------------|-------|------------|
| Soil Moisture | Analog (12-bit ADC) | 0–4095 | 12-bit (4096 levels) |
| Rain Sensor | Digital | HIGH/LOW | Binary |
| DHT11 Temp | Digital | 0–50°C | ±2°C |
| DHT11 Humidity | Digital | 20–90% RH | ±5% |
| Flow Sensor | Pulse (interrupt) | 0.3–6 L/min | ~7.5 pulses/litre |
| PWM Output | PWM (8-bit) | 0–255 | 8-bit (256 levels) |

---

## 3. ESP32 Firmware

### 3.1 Architecture

The firmware follows a cooperative multitasking model with a 5-second sensor polling loop:

```
┌─────────────────────────────────────────────────┐
│                    setup()                       │
│  1. Serial.begin(115200)                        │
│  2. dht.begin()                                  │
│  3. ledcAttach(PIN_PUMP_PWM, 1000, 8)           │
│  4. pinMode + attachInterrupt                    │
│  5. [Calibration mode if enabled]                │
│  6. connectWiFi() → connectMQTT()               │
│  7. updateDeviceStatus("online")                 │
│  8. fetchCropProfile()                           │
└──────────────────────┬──────────────────────────┘
                       ▼
┌─────────────────────────────────────────────────┐
│                     loop()                       │
│                                                  │
│  ┌─ connectWiFi() / connectMQTT() / mqtt.loop() │
│  │                                               │
│  ├─ Safety Timeout Check                         │
│  │   if (manualOverride && millis > 2min)        │
│  │     → pump off, log end, alert                │
│  │                                               │
│  ├─ 5-Second Sensor Loop                         │
│  │   Read: moisture, temp, humidity, rain, flow  │
│  │   POST → sensor_readings table                │
│  │   Alert: rain edge detection                  │
│  │   Alert: soil dry (with 10min cooldown)       │
│  │                                               │
│  └─ Auto-Irrigation Decision                     │
│      if (!manualOverride && !rain && dry)        │
│        check weather → run pump → log            │
└─────────────────────────────────────────────────┘
```

### 3.2 State Machine

| State | Trigger | Transition |
|-------|---------|------------|
| IDLE | System boot | → MONITORING |
| MONITORING | moisture < threshold AND !rain AND weather OK | → AUTO_IRRIGATING |
| MONITORING | User sends `pump_on` via MQTT | → MANUAL_PUMPING |
| AUTO_IRRIGATING | duration reaches `irrigateSecs` | → MONITORING |
| MANUAL_PUMPING | User sends `pump_off` OR 2-min timeout | → MONITORING |

### 3.3 Timing Parameters

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `INTERVAL_MS` | 5000 ms | Sensor polling interval |
| `MANUAL_TIMEOUT_MS` | 120000 ms (2 min) | Safety limit for manual pump |
| `ALERT_COOLDOWN_SOIL_MS` | 600000 ms (10 min) | Soil dry alert debounce |
| PWM Frequency | 1000 Hz | MOSFET switching frequency |
| PWM Resolution | 8-bit | Duty cycle granularity (0–255) |

---

## 4. Sensor Mathematics & Calibration

### 4.1 Soil Moisture Conversion

The capacitive soil moisture sensor outputs an analog voltage inversely proportional to soil water content. The ESP32's 12-bit ADC converts this to a raw value (0–4095).

**Conversion Formula:**

```
moisture_pct = constrain(
    map(raw_adc, MOISTURE_AIR_RAW, MOISTURE_WATER_RAW, 0, 100),
    0, 100
)
```

**Expanded Mathematical Form:**

```
moisture_pct = clamp(
    (raw_adc - MOISTURE_AIR_RAW) / (MOISTURE_WATER_RAW - MOISTURE_AIR_RAW) × 100,
    0, 100
)
```

**Calibration Values (from config.h):**

| Condition | Raw ADC Value | Moisture % |
|-----------|--------------|------------|
| Dry air | 3511 | 0% |
| Submerged in water | 1277 | 100% |
| ADC range | 3511 - 1277 = 2234 | 100% span |

**Example Calculation:**

```
raw_adc = 2500

moisture_pct = (2500 - 3511) / (1277 - 3511) × 100
             = (-1011) / (-2234) × 100
             = 0.4526 × 100
             = 45.26%
             ≈ 45%
```

**Key Insight:** Higher raw ADC = drier soil, lower raw ADC = wetter soil. This is because the capacitive sensor's capacitance increases with moisture, lowering the output voltage.

### 4.2 Flow Rate Calculation

The YF-S201 flow sensor generates pulses proportional to water flow. The K-factor is approximately 7.5 pulses per litre.

**Formula:**

```
flowLitres = (pulses / 7.5 / 60) × (INTERVAL_MS / 1000)
```

**Derivation:**

```
flowLitres = pulses × (1 litre / 7.5 pulses) × (INTERVAL_MS / 60000 ms)
```

**Example:**

```
pulses = 10 (in 5 seconds)
flowLitres = (10 / 7.5 / 60) × (5000 / 1000)
           = 0.0222 × 5
           = 0.111 litres
```

### 4.3 Rain Detection

```
rainDetected = RAIN_SENSOR_INVERT ? (raw == HIGH) : (raw == LOW)
```

With `RAIN_SENSOR_INVERT = false` (default for YL-38):
- **LOW (0)** = Rain detected (water bridges the sensor traces)
- **HIGH (1)** = No rain (dry sensor)

---

## 5. PWM Pump Control

### 5.1 PWM Fundamentals

The D4184 MOSFET module receives a PWM signal from GPIO 2 to control pump speed. This replaces the previous relay-based ON/OFF approach.

**Configuration:**

| Parameter | Value |
|-----------|-------|
| PWM Channel | GPIO 2 |
| Frequency | 1000 Hz |
| Resolution | 8-bit (0–255) |
| Default Duty | 200 (~78%) |

### 5.2 Duty Cycle to Percentage

```
pump_speed_pct = (duty / 255) × 100
```

| PWM Duty | Speed % | Use Case |
|----------|---------|----------|
| 0 | 0% | Pump OFF |
| 64 | 25% | Light drip irrigation |
| 128 | 50% | Moderate watering |
| 200 | 78% | Default (configurable per crop) |
| 255 | 100% | Maximum flow |

### 5.3 Water Usage Estimation

The firmware estimates water consumption based on PWM duty cycle and runtime:

```
waterUsed_litres = (durationSecs / 60) × (duty / 255) × 0.5
```

**Where:**
- `durationSecs / 60` = runtime in minutes
- `duty / 255` = speed factor (0.0 to 1.0)
- `0.5` = base flow rate in litres/minute at 100% duty

**Example:**

```
durationSecs = 60 (1 minute)
duty = 200 (~78%)

waterUsed = (60/60) × (200/255) × 0.5
          = 1.0 × 0.784 × 0.5
          = 0.392 litres
```

### 5.4 PWM API (ESP32 Core 3.x)

```cpp
// Setup
ledcAttach(PIN_PUMP_PWM, 1000, 8);  // pin, frequency, resolution

// Control
ledcWrite(PIN_PUMP_PWM, duty);  // duty: 0-255
```

---

## 6. Auto-Irrigation Decision Logic

### 6.1 Decision Tree

```
┌─────────────────────────────────┐
│   Is manualOverride active?     │
└──────────────┬──────────────────┘
               │
         No    │    Yes → Skip auto-irrigation
               ▼
┌─────────────────────────────────┐
│   Is rain detected?             │
└──────────────┬──────────────────┘
               │
         No    │    Yes → Skip (rain provides water)
               ▼
┌─────────────────────────────────┐
│   Is moisture < moistureLow?    │
│   (default: 30%)                │
└──────────────┬──────────────────┘
               │
         Yes   │    No → Skip (soil is moist enough)
               ▼
┌─────────────────────────────────┐
│   Is forecast rain < rainSkip?  │
│   (default: 60%)                │
└──────────────┬──────────────────┘
               │
         Yes   │    No → Skip (rain coming soon)
               ▼
┌─────────────────────────────────┐
│   RUN PUMP for irrigateSecs     │
│   (default: 60 seconds)         │
└─────────────────────────────────┘
```

### 6.2 Decision Formula

```
should_irrigate = !manualOverride
               && !rain_detected
               && (moisture < cropProfile.moistureLow)
               && (forecast_rain_pct < cropProfile.rainSkipPct)
```

### 6.3 Crop Profile Parameters

| Parameter | Column | Default | Description |
|-----------|--------|---------|-------------|
| Moisture Low | `moisture_threshold_low` | 30% | Trigger irrigation below this |
| Moisture High | `moisture_threshold_high` | 70% | Upper bound (informational) |
| Duration | `irrigation_duration_s` | 60s | How long to run the pump |
| Rain Skip | `weather_sensitivity` | 60% | Skip if forecast rain > this |
| PWM Duty | `pwm_duty` | 200 | Pump speed (0–255) |

### 6.4 Auto-Irrigation Sequence

```
1. Log pump start → postPumpLogStart(moisture_before, "auto")
2. Set PWM → setPumpPwm(autoPwmDuty)
3. Block for duration → delay(irrigateSecs × 1000)
4. Stop PWM → setPumpPwm(0)
5. Read moisture after → analogReadMoisture()
6. Calculate water used → (secs/60) × (duty/255) × 0.5
7. Log pump end → patchPumpLogEnd(id, moisture_after, duration, water)
8. Send alerts → auto_irrigation_started / auto_irrigation_stopped
```

---

## 7. Supabase Database Schema

### 7.1 Entity Relationship Diagram

```
┌──────────────┐       ┌──────────────┐       ┌──────────────────┐
│    users     │       │   devices    │       │  sensor_readings │
├──────────────┤       ├──────────────┤       ├──────────────────┤
│ id (PK)      │──┐    │ id (PK)      │──┐    │ id (PK)          │
│ username     │  │    │ user_id (FK) │◀─┘    │ device_id (FK)   │
│ email        │  │    │ name         │  └───▶│ soil_moisture    │
│ temp_unit    │  │    │ status       │       │ temperature_c    │
│ volume_unit  │  │    │ last_seen    │       │ humidity         │
│ timezone     │  │    │ crop_profile_│──┐    │ rain_detected    │
│ location_lat │  │    │   id (FK)    │  │    │ flow_litres      │
│ location_lon │  │    │ claimed_at   │  │    │ recorded_at      │
│ ...          │  │    │ created_at   │  │    │ created_at       │
└──────────────┘  │    └──────────────┘  │    └──────────────────┘
                  │                      │
                  │    ┌──────────────┐  │    ┌──────────────────┐
                  │    │crop_profiles │  │    │    pump_logs     │
                  │    ├──────────────┤  │    ├──────────────────┤
                  └───▶│ id (PK)      │  │    │ id (PK)          │
                       │ user_id (FK) │  │    │ device_id (FK)   │
                       │ name         │  │    │ pump_on_at       │
                       │ moisture_    │  │    │ duration_seconds │
                       │   thresh_low │  │    │ water_used_litres│
                       │ moisture_    │  │    │ moisture_before  │
                       │   thresh_high│  │    │ moisture_after   │
                       │ irrigation_  │  │    │ rain_detected    │
                       │   duration_s │  │    │ trigger_type     │
                       │ weather_     │  │    │ created_at       │
                       │   sensitivity│  │    └──────────────────┘
                       │ pwm_duty     │  │
                       │ plant_name   │  │    ┌──────────────────┐
                       │ perenual_*   │  │    │     alerts       │
                       │ created_at   │  │    ├──────────────────┤
                       └──────────────┘  │    │ id (PK)          │
                                         │    │ device_id (FK)   │
                                         └───▶│ alert_type       │
                                              │ message          │
                                              │ resolved         │
                                              │ created_at       │
                                              └──────────────────┘
```

### 7.2 Table Specifications

#### sensor_readings (2,290 rows)

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | bigint | No | auto | Primary key |
| `device_id` | uuid | Yes | — | FK → devices.id |
| `soil_moisture` | integer | Yes | — | 0–100% |
| `temperature_c` | numeric | Yes | — | Celsius |
| `humidity` | numeric | Yes | — | Relative humidity % |
| `rain_detected` | boolean | Yes | false | Rain sensor state |
| `flow_litres` | numeric | Yes | — | Water flow in interval |
| `recorded_at` | timestamptz | Yes | now() | When reading was taken |
| `created_at` | timestamptz | Yes | = recorded_at | Insert timestamp |

#### pump_logs (48 rows)

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | bigint | No | auto | Primary key |
| `device_id` | uuid | Yes | — | FK → devices.id |
| `pump_on_at` | timestamptz | Yes | now() | Cycle start time |
| `duration_seconds` | integer | Yes | — | Total run time |
| `water_used_litres` | numeric | Yes | — | Estimated water used |
| `moisture_before` | integer | Yes | — | Soil moisture before |
| `moisture_after` | integer | Yes | — | Soil moisture after |
| `rain_detected` | boolean | Yes | false | Rain state during cycle |
| `trigger_type` | text | Yes | 'auto' | 'auto' or 'manual' |
| `created_at` | timestamptz | Yes | now() | Insert timestamp |

#### crop_profiles (2 rows)

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | bigint | No | auto | Primary key |
| `user_id` | uuid | Yes | — | FK → users.id |
| `name` | text | No | — | Profile name |
| `moisture_threshold_low` | integer | Yes | 30 | Auto-irrigation trigger |
| `moisture_threshold_high` | integer | Yes | 70 | Upper moisture bound |
| `irrigation_duration_s` | integer | Yes | 60 | Pump runtime |
| `weather_sensitivity` | integer | Yes | 60 | Rain skip threshold % |
| `pwm_duty` | integer | Yes | 200 | Pump speed (0–255) |
| `plant_name` | text | Yes | — | Plant species name |
| `perenual_species_id` | integer | Yes | — | External plant API ID |
| `perenual_data` | jsonb | Yes | — | Cached plant care data |
| `perenual_care_data` | jsonb | Yes | — | Processed care instructions |

#### devices (1 row)

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | uuid | No | gen_random_uuid() | Primary key |
| `user_id` | uuid | Yes | — | FK → users.id |
| `name` | text | Yes | 'My Plant' | Device display name |
| `status` | text | Yes | 'offline' | 'online' or 'offline' |
| `last_seen` | timestamptz | Yes | — | Last sensor reading time |
| `crop_profile_id` | bigint | Yes | — | FK → crop_profiles.id |
| `claimed_at` | timestamptz | Yes | — | When device was linked |
| `created_at` | timestamptz | Yes | now() | Registration timestamp |

#### alerts (20 rows)

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | bigint | No | auto | Primary key |
| `device_id` | uuid | Yes | — | FK → devices.id |
| `alert_type` | text | Yes | — | Type identifier |
| `message` | text | Yes | — | Human-readable message |
| `resolved` | boolean | Yes | false | Whether alert was handled |
| `created_at` | timestamptz | Yes | now() | Alert timestamp |

#### users (1 row)

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | uuid | No | — | PK, FK → auth.users.id |
| `username` | text | Yes | — | Display name |
| `email` | text | Yes | — | Email address |
| `temp_unit` | text | Yes | 'celsius' | 'celsius' or 'fahrenheit' |
| `volume_unit` | text | Yes | 'litres' | 'litres' or 'gallons' |
| `wind_unit` | text | Yes | 'km/h' | Wind speed unit |
| `precipitation_unit` | text | Yes | 'mm' | Rain unit |
| `aqi_type` | text | Yes | 'us' | AQI standard |
| `timezone` | text | Yes | 'UTC' | User timezone |
| `location_lat` | text | Yes | '19.0760' | Latitude |
| `location_lon` | text | Yes | '72.8777' | Longitude |
| `pump_alerts` | boolean | Yes | true | Notification toggle |
| `soil_moisture_alerts` | boolean | Yes | true | Notification toggle |
| `weather_alerts` | boolean | Yes | true | Notification toggle |
| `fertigation_reminders` | boolean | Yes | true | Notification toggle |
| `device_offline_alerts` | boolean | Yes | true | Notification toggle |
| `weekly_summary` | boolean | Yes | false | Email summary toggle |

### 7.3 Foreign Key Relationships

| Source | Target | Constraint Name |
|--------|--------|----------------|
| `users.id` | `auth.users.id` | users_id_fkey |
| `devices.user_id` | `users.id` | devices_user_id_fkey |
| `devices.crop_profile_id` | `crop_profiles.id` | fk_crop_profile |
| `sensor_readings.device_id` | `devices.id` | sensor_readings_device_id_fkey |
| `pump_logs.device_id` | `devices.id` | pump_logs_device_id_fkey |
| `alerts.device_id` | `devices.id` | alerts_device_id_fkey |
| `crop_profiles.user_id` | `users.id` | crop_profiles_user_id_fkey |
| `fertigation_logs.device_id` | `devices.id` | fertigation_logs_device_id_fkey |
| `fertigation_logs.crop_profile_id` | `crop_profiles.id` | fertigation_logs_crop_profile_id_fkey |
| `device_commands.device_id` | `devices.id` | device_commands_device_id_fkey |
| `device_tokens.user_id` | `auth.users.id` | device_tokens_user_id_fkey |
| `user_profiles.user_id` | `auth.users.id` | user_profiles_user_id_fkey |

---

## 8. Flutter Mobile Application

### 8.1 Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter App                               │
│                                                              │
│  ┌─────────────┐   ┌──────────────┐   ┌──────────────────┐  │
│  │   Screens   │   │   Widgets    │   │    Services      │  │
│  │   (15)      │   │   (9)        │   │   (2)            │  │
│  │             │   │              │   │                  │  │
│  │ dashboard   │   │ device_health│   │ mqtt_service     │  │
│  │ irrigation  │   │ toggle_tile  │   │ notification_svc │  │
│  │ water_usage │   │ dropdown_tile│   │                  │  │
│  │ weather     │   │ editable_text│   │                  │  │
│  │ alerts      │   │ settings_sec │   │                  │  │
│  │ crop_profiles│  │ read_only    │   │                  │  │
│  │ settings    │   │ inline_pwd   │   │                  │  │
│  │ profile     │   │ delete_acct  │   │                  │  │
│  │ ...         │   │ double_back  │   │                  │  │
│  └──────┬──────┘   └──────────────┘   └────────┬─────────┘  │
│         │                                       │            │
│         └───────────────┬───────────────────────┘            │
│                         ▼                                    │
│              ┌─────────────────────┐                         │
│              │  AppStateProvider   │                         │
│              │  (Provider/State)   │                         │
│              │                     │                         │
│              │  - deviceId         │                         │
│              │  - sensorHistory    │                         │
│              │  - latestSensorData │                         │
│              │  - cropProfiles     │                         │
│              │  - alerts           │                         │
│              │  - volumeUnit       │                         │
│              │  - tempUnit         │                         │
│              └────────┬────────────┘                         │
│                       │                                      │
│         ┌─────────────┼─────────────────┐                   │
│         ▼             ▼                 ▼                   │
│  ┌──────────┐  ┌────────────┐  ┌──────────────┐            │
│  │ Supabase │  │  Realtime  │  │   GoRouter   │            │
│  │   REST   │  │ WebSocket  │  │  Navigation  │            │
│  └──────────┘  └────────────┘  └──────────────┘            │
└─────────────────────────────────────────────────────────────┘
```

### 8.2 Screen Inventory

| Screen | File | Purpose |
|--------|------|---------|
| Login | `login_screen.dart` | User authentication via Supabase Auth |
| Dashboard | `dashboard_screen.dart` | Real-time sensor data, manual pump control |
| Device Management | `device_management_screen.dart` | Add/remove ESP32 devices |
| Link Device | `link_device_screen.dart` | Device linking flow |
| Device Choice | `device_choice_screen.dart` | Device selection |
| Crop Profiles | `crop_profiles_screen.dart` | Configure irrigation thresholds |
| Irrigation History | `irrigation_screen.dart` | Soil moisture trends, daily averages |
| Water Usage | `water_usage_screen.dart` | Water consumption analytics, efficiency |
| Weather | `weather_screen.dart` | Weather forecast display |
| Alerts | `alerts_screen.dart` | Device alerts and notifications |
| Fertigation | `fertigation_screen.dart` | Fertilizer/plant management |
| Profile | `profile_screen.dart` | User profile management |
| Settings | `settings_screen.dart` | App preferences |
| Preferences | `preferences_screen.dart` | User preferences |
| More | `more_screen.dart` | Additional options |

### 8.3 State Management (AppStateProvider)

The app uses Provider for state management with a single `AppStateProvider` class that manages:

| State Property | Type | Description |
|---------------|------|-------------|
| `deviceId` | String? | Currently selected device UUID |
| `isLoading` | bool | Global loading state |
| `latestSensorData` | Map | Most recent sensor reading |
| `sensorHistory` | List | Historical sensor readings |
| `cropProfiles` | List | Available crop profiles |
| `alerts` | List | Device alerts |
| `volumeUnit` | String | User's volume preference |
| `tempUnit` | String | User's temperature preference |

### 8.4 Key Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `flutter` | 3.x | UI framework |
| `supabase_flutter` | ^2.12.0 | Backend SDK |
| `provider` | ^6.1.5+1 | State management |
| `go_router` | ^17.1.0 | Navigation |
| `fl_chart` | ^1.1.1 | Data visualization |
| `mqtt_client` | ^10.2.1 | MQTT communication |
| `firebase_messaging` | ^15.1.3 | Push notifications |
| `flutter_local_notifications` | ^17.2.2 | Local notifications |
| `shared_preferences` | ^2.3.3 | Local storage |
| `lottie` | ^3.1.2 | Animations |

---

## 9. Data Flow Architecture

### 9.1 Sensor Data Flow (5-second interval)

```
┌──────────┐     HTTPS POST      ┌──────────────┐     Realtime       ┌────────┐
│  ESP32   │ ──────────────────▶ │   Supabase   │ ─────────────────▶ │Flutter │
│          │   /rest/v1/         │   Database   │     WebSocket      │  App   │
│  Sensors │   sensor_readings   │              │                    │        │
└──────────┘                     └──────────────┘                    └────────┘

Payload:
{
  "device_id": "62e19bc1-...",
  "soil_moisture": 45,
  "temperature_c": 28.5,
  "humidity": 65.0,
  "rain_detected": false,
  "flow_litres": 0.111
}
```

### 9.2 Manual Pump Control Flow

```
┌────────┐     MQTT Publish     ┌──────────┐     MQTT Subscribe    ┌─────────┐
│Flutter │ ──────────────────▶ │  HiveMQ  │ ────────────────────▶ │  ESP32  │
│  App   │   devices/{id}/     │  Cloud   │   devices/{id}/       │         │
│        │   control            │          │   control              │         │
└────────┘                     └──────────┘                        └────┬────┘
                                                                       │
                                                                       ▼
                                                                 ┌──────────┐
                                                                 │  D4184   │
                                                                 │  MOSFET  │
                                                                 │  → Pump  │
                                                                 └──────────┘

MQTT Payload (pump_on):
{
  "command": "pump_on",
  "pwm": 200
}

MQTT Payload (pump_off):
{
  "command": "pump_off"
}
```

### 9.3 Pump Log Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                     PUMP LOG LIFECYCLE                           │
│                                                                  │
│  1. START: postPumpLogStart(moisture_before, "auto"/"manual")   │
│     → INSERT into pump_logs                                     │
│     → Returns log ID                                            │
│                                                                  │
│  2. RUN: Pump operates for duration                             │
│                                                                  │
│  3. END: patchPumpLogEnd(id, moisture_after, duration, water)   │
│     → UPDATE pump_logs SET moisture_after, duration_seconds,    │
│       water_used_litres WHERE id = logId                         │
│                                                                  │
│  Final Record:                                                   │
│  ┌──────────────┬──────────┬──────────┬──────────┬────────────┐ │
│  │ pump_on_at   │ duration │ water    │ moist_b4 │ moist_after│ │
│  ├──────────────┼──────────┼──────────┼──────────┼────────────┤ │
│  │ 2025-04-01   │ 60       │ 0.392    │ 28       │ 45         │ │
│  │ 10:30:00Z    │ seconds  │ litres   │ %        │ %          │ │
│  └──────────────┴──────────┴──────────┴──────────┴────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

---

## 10. Communication Protocols

### 10.1 MQTT Topics

| Topic Pattern | Direction | Purpose |
|--------------|-----------|---------|
| `devices/{device_id}/control` | App → ESP32 | Pump commands |

### 10.2 MQTT Message Format

| Command | Payload | Response |
|---------|---------|----------|
| `pump_on` | `{"command": "pump_on", "pwm": 200}` | Pump starts at specified PWM |
| `pump_off` | `{"command": "pump_off"}` | Pump stops, PWM = 0 |
| `set_pwm` | `{"command": "set_pwm", "value": 150}` | PWM updated without starting pump |

### 10.3 Supabase REST API Calls

| Function | Method | Endpoint | Purpose |
|----------|--------|----------|---------|
| `postSensorReading` | POST | `/rest/v1/sensor_readings` | Upload sensor data |
| `postPumpLogStart` | POST | `/rest/v1/pump_logs` | Start pump cycle log |
| `patchPumpLogEnd` | PATCH | `/rest/v1/pump_logs?id=eq.{id}` | End pump cycle log |
| `fetchCropProfile` | GET | `/rest/v1/devices?select=crop_profiles(...)` | Get irrigation config |
| `updateDeviceStatus` | PATCH | `/rest/v1/devices?id=eq.{id}` | Update online/offline |
| `postAlert` | POST | `/rest/v1/alerts` | Create alert record |

### 10.4 Weather API (Open-Meteo)

| Parameter | Value | Purpose |
|-----------|-------|---------|
| Base URL | `https://api.open-meteo.com/v1/forecast` | Free weather API |
| Latitude | 19.0760 | Mumbai |
| Longitude | 72.8777 | Mumbai |
| Forecast | Next 6 hours | Rain probability |
| Authentication | None required | Free tier |

---

## 11. Efficiency Scoring

The water usage screen calculates a daily efficiency score (0–100) based on three factors:

### 11.1 Formula

```
efficiency = 0.4 × mScore + 0.4 × wScore + 0.2 × rainBonus
```

### 11.2 Moisture Score (40% weight)

```
gain = clamp(moisture_after - moisture_before, 0, 40)
mScore = (gain / 40) × 100
```

| Moisture Gain | mScore | Interpretation |
|--------------|--------|----------------|
| 0% | 0 | No improvement |
| 20% | 50 | Moderate improvement |
| 40%+ | 100 | Maximum improvement |

### 11.3 Water Rate Score (40% weight)

```
lpm = waterLitres / runtimeMinutes  // litres per minute
wScore = clamp(1.0 - |lpm - 1.5| / 3.0, 0, 1) × 100
```

The optimal water rate is **1.5 L/min**. Deviations from this reduce the score:

| LPM | wScore | Interpretation |
|-----|--------|----------------|
| 1.5 | 100 | Optimal flow rate |
| 0.5 | 66.7 | Low flow |
| 2.5 | 66.7 | High flow |
| 0.0 or 4.5 | 0 | Very inefficient |

### 11.4 Rain Bonus (20% weight)

```
rainBonus = rainDetected ? 100 : 0
```

If rain was detected during the day, the system gets a full 20-point bonus since natural watering is most efficient.

### 11.5 Efficiency Color Coding

| Score Range | Color | Meaning |
|-------------|-------|---------|
| 75–100% | Teal (#2D6A4F) | Excellent |
| 50–74% | Orange (#F97316) | Moderate |
| 0–49% | Red (error) | Poor |

### 11.6 Example Calculation

```
Day with:
- moisture_before: 30%
- moisture_after: 55%
- waterLitres: 1.5
- runtimeMinutes: 1
- rainDetected: false

mScore = clamp(55-30, 0, 40) / 40 × 100 = 25/40 × 100 = 62.5
lpm = 1.5 / 1 = 1.5
wScore = clamp(1.0 - |1.5-1.5|/3.0, 0, 1) × 100 = 100
rainBonus = 0

efficiency = 0.4 × 62.5 + 0.4 × 100 + 0.2 × 0
           = 25 + 40 + 0
           = 65%
```

---

## 12. Edge Functions

### 12.1 Function Inventory

| Function | Trigger | Purpose |
|----------|---------|---------|
| `perenual-lookup` | Manual/API | Fetch plant care data from Perenual API with caching |
| `weekly-summary` | Cron (weekly) | Send weekly email summaries to users |
| `purge-old-logs` | Cron (daily) | Delete pump logs older than 14 days |
| `send-alert-notification` | Webhook (on alerts insert) | Send FCM push notifications for alerts |

### 12.2 Alert Types

| Alert Type | Trigger | Message Template |
|-----------|---------|-----------------|
| `pump_on` | Manual pump start | "Manual pump activated via app." |
| `pump_off` | Manual pump stop | "Manual pump stopped via app." |
| `pump_timeout` | Safety timeout (2 min) | "Pump stopped automatically after the 2-minute safety limit." |
| `rain_started` | Rain sensor edge (LOW) | "Rain detected — automatic irrigation paused." |
| `rain_stopped` | Rain sensor edge (HIGH) | "Rain stopped — automatic irrigation resumed." |
| `soil_dry` | Moisture < threshold (10min cooldown) | "Soil moisture at X% — below threshold of Y%." |
| `auto_irrigation_started` | Auto irrigation begins | "Auto irrigation started — soil moisture at X%." |
| `auto_irrigation_stopped` | Auto irrigation ends | "Auto irrigation complete — soil moisture now X% after Y seconds." |

### 12.3 Data Retention

The `purge-old-logs` edge function deletes pump logs older than 14 days. Sensor readings are not automatically purged (2,290+ rows currently stored).

---

## 13. Security Model

### 13.1 Row Level Security (RLS)

All tables have RLS enabled. The security model ensures:

| Rule | Description |
|------|-------------|
| User isolation | Users can only see their own devices |
| Device scoping | Devices can only write to their own sensor readings |
| Profile access | Crop profiles scoped to user via device ownership |
| Alert privacy | Alerts visible only to device owner |

### 13.2 Authentication Flow

```
┌────────┐     ┌──────────────┐     ┌──────────────┐
│Flutter │────▶│  Supabase    │────▶│  auth.users  │
│  App   │     │  Auth SDK    │     │  (PostgreSQL)│
└────────┘     └──────────────┘     └──────────────┘
     │                                      │
     │  JWT Token                           │
     │◀─────────────────────────────────────┘
     │
     │  All subsequent requests include:
     │  Authorization: Bearer <JWT>
     ▼
┌──────────────┐
│  RLS Policies│
│  filter by   │
│  user_id     │
└──────────────┘
```

### 13.3 Secrets Management

| Secret | Location | Protection |
|--------|----------|------------|
| WiFi Password | `esp32/config.h` | Stored on device flash |
| Supabase Anon Key | `esp32/config.h` | Public-safe, RLS protected |
| MQTT Password | `esp32/config.h` | Device credentials |
| FCM Service Account | Supabase Secrets | Edge function only |
| Perenual API Key | Edge function env | Server-side only |

### 13.4 Transport Security

| Connection | Protocol | Security |
|-----------|----------|----------|
| ESP32 → Supabase | HTTPS (REST) | TLS (WiFiClientSecure.setInsecure) |
| ESP32 → HiveMQ | MQTT over TLS | Port 8883, TLS |
| Flutter → Supabase | HTTPS | TLS via supabase_flutter SDK |
| Flutter → HiveMQ | MQTT over TLS | TLS via mqtt_client package |

---

## Appendix A: Project Statistics

| Category | Count |
|----------|-------|
| ESP32 Source Files | 5 |
| Flutter Dart Files | 35 |
| Screens | 15 |
| Widgets | 9 |
| Services | 2 |
| Edge Functions | 4 |
| Database Tables | 10 |
| Sensor Readings (stored) | 2,290+ |
| Pump Logs (stored) | 48 |
| Asset Files | 741+ |
| Documentation Files | 6 |

## Appendix B: File Checklist

### ESP32 Firmware

| File | Lines | Purpose |
|------|-------|---------|
| `esp32.ino` | 327 | Main firmware |
| `config.h` | 65 | Configuration constants |
| `config.h.example` | — | Template |
| `supabase_client.h` | 147 | REST API client |
| `weather_client.h` | — | Open-Meteo API client |

### Flutter Application

| Directory | Files | Purpose |
|-----------|-------|---------|
| `lib/` | 35 | Dart source code |
| `lib/screens/` | 15 | UI screens |
| `lib/widgets/` | 9 | Reusable components |
| `lib/services/` | 2 | MQTT, notifications |
| `lib/providers/` | 1 | State management |
| `lib/utils/` | 3 | Helpers, converters |

## Appendix C: GPIO Pin Reference

```
ESP32 DevKit V1 Pinout:

GPIO 2   ─── PWM Pump (D4184 MOSFET)
GPIO 4   ─── DHT11 Data
GPIO 18  ─── Flow Sensor (Interrupt, FALLING)
GPIO 34  ─── Soil Moisture (Analog In, ADC1)
GPIO 35  ─── Rain Sensor (Digital In)

Note: GPIO 34 and 35 are input-only pins on ESP32.
```
