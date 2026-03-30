# SISSv2 - Smart Irrigation System Architecture

## Project Overview

SISSv2 is a complete IoT-based smart irrigation system consisting of:
- **ESP32 Firmware** - Embedded C++ code for sensor data collection and pump control
- **Flutter Mobile App** - Cross-platform mobile application for monitoring and control
- **Supabase Backend** - Database, authentication, and edge functions
- **MQTT Broker** - HiveMQ Cloud for real-time device communication

---

## Directory Structure

```
SISSv2/
├── app/                         # Flutter mobile application
│   ├── lib/                     # Dart source code
│   │   ├── main.dart            # App entry point
│   │   ├── router.dart          # GoRouter navigation
│   │   ├── theme.dart           # App theming
│   │   ├── providers/          # State management
│   │   ├── screens/             # UI pages (15 screens)
│   │   ├── widgets/             # Reusable components (9 files)
│   │   ├── services/            # Business logic
│   │   └── utils/               # Helper functions
│   ├── android/                 # Android platform files
│   ├── ios/                     # iOS platform files
│   ├── assets/                  # Images, fonts, animations
│   ├── supabase/                # Database migrations & edge functions
│   ├── pubspec.yaml             # Flutter dependencies
│   └── README.md                # App-specific readme
├── esp32/                       # ESP32 firmware source
│   ├── esp32.ino                # Main firmware code
│   ├── config.h                 # WiFi, MQTT, Supabase credentials
│   ├── supabase_client.h        # REST API client
│   └── weather_client.h         # Open-Meteo API client
├── docs/                        # Documentation
│   ├── project-architecture.md  # This file
│   ├── edge-functions.md        # Supabase Edge Functions reference
│   ├── Hardware Components.md   # Hardware setup guide
│   ├── SISSv2_Architecture_and_Steps.md # Original architecture
│   └── Features list.md         # Feature list
├── supabase/                    # Supabase local config
└── README.md                    # Project readme
```

---

## Part 1: ESP32 Firmware

### Overview
The ESP32 firmware reads sensors, posts data to Supabase, and responds to manual pump commands via MQTT.

### Files

#### 1.1 esp32.ino
**Purpose:** Main firmware orchestrator

| Component | Description |
|-----------|-------------|
| **Hardware Setup** | DHT11 temperature/humidity, soil moisture sensor, rain sensor, flow sensor, pump relay |
| **MQTT Callback** | Receives `pump_on` / `pump_off` commands from Flutter |
| **Sensor Loop** | Runs every 5 seconds, posts to Supabase |
| **Auto-Irrigation** | Checks moisture, rain sensor, and weather forecast before watering |
| **Manual Override** | 2-minute safety timeout for manual pump control |

**Key Functions:**
- `mqttCallback()` - Handles MQTT commands
- `analogReadMoisture()` - Reads soil moisture (0-100%)
- `connectWiFi()` / `connectMQTT()` - Maintains connections

#### 1.2 config.h
**Purpose:** All configuration constants

| Section | Contents |
|---------|----------|
| **WiFi** | SSID, password |
| **Supabase** | URL, anon key, device UUID |
| **HiveMQ** | Host, port, credentials, MQTT topics |
| **Location** | Latitude/longitude for weather API |
| **Pins** | GPIO mappings for sensors and relay |
| **Defaults** | Fallback thresholds if no crop profile exists |

#### 1.3 supabase_client.h
**Purpose:** All Supabase REST API calls

| Function | Purpose |
|----------|---------|
| `postSensorReading()` | Upload moisture, temp, humidity, rain, flow data |
| `postPumpLogStart()` | Record pump cycle start |
| `patchPumpLogEnd()` | Update pump cycle end (duration, water used) |
| `fetchCropProfile()` | Get irrigation thresholds via relational query |
| `updateDeviceStatus()` | Update device online/offline status |

**Database Tables Used:**
- `sensor_readings` - Time-series sensor data
- `pump_logs` - Irrigation cycle history
- `devices` - Device registry and status
- `crop_profiles` - User-defined irrigation settings

#### 1.4 weather_client.h
**Purpose:** Fetch rain probability from Open-Meteo

**API:** Open-Meteo (free, no key required)

**Returns:** 0-100% rain probability for next 6 hours

**Used by:** Auto-irrigation logic to skip watering if rain expected

---

## Part 2: Flutter Mobile Application

### Overview
Cross-platform mobile app built with Flutter for iOS/Android. Uses Provider for state management and Supabase for backend communication.

### Directory Structure

```
app/lib/
├── main.dart                         # App entry point
├── router.dart                       # GoRouter navigation
├── theme.dart                        # App theming (colors, typography)
├── providers/
│   └── app_state_provider.dart       # Global state management
├── screens/
│   ├── login_screen.dart             # User authentication
│   ├── dashboard_screen.dart         # Main view with sensor data, pump control
│   ├── device_management_screen.dart # Add/remove ESP32 devices
│   ├── link_device_screen.dart       # Device linking flow
│   ├── device_choice_screen.dart     # Device selection
│   ├── crop_profiles_screen.dart     # Configure irrigation thresholds
│   ├── irrigation_screen.dart        # View irrigation history
│   ├── water_usage_screen.dart       # Water consumption analytics
│   ├── weather_screen.dart           # Weather forecast display
│   ├── alerts_screen.dart            # Device alerts and notifications
│   ├── fertigation_screen.dart       # Fertilizer/plant management
│   ├── profile_screen.dart           # User profile management
│   ├── settings_screen.dart          # App preferences
│   ├── preferences_screen.dart       # User preferences
│   └── more_screen.dart              # Additional options
├── services/
│   ├── mqtt_service.dart             # MQTT client for HiveMQ
│   └── notification_service.dart      # Push notifications (FCM)
├── widgets/
│   ├── device_health_tile.dart       # Device status card
│   ├── toggle_setting_tile.dart      # Boolean setting control
│   ├── dropdown_setting_tile.dart    # Selection setting control
│   ├── editable_text_tile.dart       # Text input setting
│   ├── settings_section.dart         # Settings group container
│   ├── read_only_tile.dart           # Display-only info tile
│   ├── inline_password_tile.dart      # Password input tile
│   └── delete_account_button.dart     # Account deletion
└── utils/
    ├── date_helpers.dart             # Date/time formatting
    ├── unit_converter.dart           # Unit conversion utilities
    └── enums.dart                    # App-wide enumerations
```

### Key Files

#### 2.1 main.dart
- App initialization
- Supabase client setup
- Provider configuration

#### 2.2 router.dart
- GoRouter navigation setup
- Route guards (auth check)
- Bottom navigation structure

#### 2.3 app_state_provider.dart
**Purpose:** Central state management for entire app

| Feature | Description |
|---------|-------------|
| Device Management | Link/unlink ESP32 devices |
| Sensor Data | Real-time sensor readings via Supabase Realtime |
| Crop Profiles | Irrigation threshold management |
| Alerts | Device alert handling |
| User Profile | Settings and preferences |

**Key Methods:**
- `init()` - Initialize app state
- `refreshSensorData()` - Fetch latest readings
- `sendMqttCommand()` - Control pump via MQTT

### Screens (15 screens)

| Screen | Purpose |
|--------|---------|
| `login_screen.dart` | User authentication |
| `dashboard_screen.dart` | Main view with sensor data, manual pump control |
| `device_management_screen.dart` | Add/remove ESP32 devices |
| `link_device_screen.dart` | Device linking flow |
| `device_choice_screen.dart` | Device selection |
| `crop_profiles_screen.dart` | Configure irrigation thresholds |
| `irrigation_screen.dart` | View irrigation history |
| `water_usage_screen.dart` | Water consumption analytics |
| `weather_screen.dart` | Weather forecast display |
| `alerts_screen.dart` | Device alerts and notifications |
| `fertigation_screen.dart` | Fertilizer/plant management |
| `settings_screen.dart` | App preferences |
| `preferences_screen.dart` | User preferences |
| `profile_screen.dart` | User profile management |
| `more_screen.dart` | Additional options |

### Services

#### 2.4 mqtt_service.dart
- Connects to HiveMQ Cloud
- Subscribes to device status topics
- Publishes pump commands

#### 2.5 notification_service.dart
- FCM token management
- Handles push notification payloads
- Navigation based on notification data

### Widgets (9 files)

| Widget | Purpose |
|--------|---------|
| `device_health_tile.dart` | Device status card |
| `toggle_setting_tile.dart` | Boolean setting control |
| `dropdown_setting_tile.dart` | Selection setting control |
| `editable_text_tile.dart` | Text input setting |
| `settings_section.dart` | Settings group container |
| `read_only_tile.dart` | Display-only info tile |
| `inline_password_tile.dart` | Password input tile |
| `delete_account_button.dart` | Account deletion |
| `double_back_press_wrapper.dart` | Prevents accidental back navigation |

### Utils (3 files)

| File | Purpose |
|------|---------|
| `date_helpers.dart` | Date/time formatting |
| `unit_converter.dart` | Unit conversion utilities |
| `enums.dart` | App-wide enumerations |

---

## Part 3: Supabase Backend

### Overview
Supabase provides PostgreSQL database, authentication, and Edge Functions.

### Database Schema

#### Tables

| Table | Purpose |
|-------|---------|
| `users` | User accounts (managed by Supabase Auth) |
| `user_profiles` | Extended user data (timezone, preferences) |
| `devices` | Registered ESP32 devices |
| `device_tokens` | FCM push tokens for notifications |
| `sensor_readings` | Time-series sensor data |
| `pump_logs` | Irrigation cycle history |
| `crop_profiles` | Per-device irrigation thresholds |
| `system_alerts` | Device-generated alerts |
| `device_commands` | Pending commands (legacy - now via MQTT) |

### Migrations

| File | Description |
|------|-------------|
| `006_user_location.sql` | Add user location fields |
| `007_unit_preferences.sql` | Add unit preference settings |
| `008_perenual_care_data.sql` | Plant care API data |

### Edge Functions

| Function | Purpose |
|----------|---------|
| `perenual-lookup` | Fetch plant care data from Perenual API with caching |
| `weekly-summary` | Send weekly email summaries to users |
| `purge-old-logs` | Delete pump logs older than 14 days |
| `send-alert-notification` | Send push notifications for alerts via FCM |

---

## Part 4: Assets

### Overview
The app includes fonts, icons, and animations for weather visualization.

### Asset Structure

```
app/assets/
├── fonts/                    # Custom fonts
│   ├── Manrope-VariableFont_wght.ttf
│   ├── Material_Icons_Outlined/
│   ├── Material_Icons_Round/
│   └── Material_Icons_Two_Tone/
├── icon/                     # App icons (master.png, compass2.jpg, UV.jpg)
├── lottie/                   # Lottie animations
│   ├── phone_portrait/       # Phone portrait animations
│   ├── phone_portrait_night/ # Night variants
│   ├── phone_landscape/      # Phone landscape animations
│   ├── phone_landscape_night/
│   ├── tablet_portrait/      # Tablet portrait animations
│   ├── tablet_portrait_night/
│   ├── tablet_landscape/     # Tablet landscape animations
│   └── tablet_landscape_night/
├── set-1/                    # Weather icon set 1 (PNG)
├── set-2/                    # Weather icon set 2 (PNG)
├── set-3/                    # Weather icon set 3 (SVG, light/dark)
├── set-4/                    # Weather icon set 4 (SVG, light/dark)
├── set-5/                    # Weather icon set 5 (SVG, light/dark)
├── set-6/                    # Weather icon set 6 (SVG, light/dark)
└── weather_icons/            # Weather icons (JSON format)
```

---

## Part 5: Data Flow Architecture

### 5.1 Sensor Data Flow

```
┌─────────────┐     ┌──────────┐     ┌───────────┐     ┌────────┐
│   ESP32    │────▶│ Supabase │────▶│ Realtime  │────▶│Flutter │
│  (Sensors) │     │   REST   │     │WebSocket  │     │  App   │
└─────────────┘     └──────────┘     └───────────┘     └────────┘
      │                   │                                   │
      │  Every 5 seconds  │      Instant push update           │
      └───────────────────┴───────────────────────────────────┘
```

**Steps:**
1. ESP32 reads sensors (moisture, temp, humidity, rain, flow)
2. Posts to `sensor_readings` table via REST API
3. Supabase Realtime pushes new record to Flutter
4. Flutter UI updates instantly

### 5.2 Manual Pump Control Flow

```
┌────────┐     ┌──────────┐     ┌─────────┐     ┌─────────────┐
│Flutter │────▶│  HiveMQ  │────▶│  ESP32  │────▶│   Pump      │
│  App   │     │   MQTT   │     │          │     │   Relay     │
└────────┘     └──────────┘     └─────────┘     └─────────────┘
    │               │                                        │
    │  Publish      │        Subscribe                        │
    │  pump_on/off  │        topic                            │
    └───────────────┴────────────────────────────────────────┘
```

**Steps:**
1. User taps pump button in Flutter
2. App publishes `pump_on` to MQTT topic
3. ESP32 receives via callback
4. Controls GPIO relay to switch pump
5. Logs pump start/end to Supabase

### 5.3 Auto-Irrigation Flow

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│   ESP32     │────▶│ Open-Meteo   │────▶│  Decision   │
│  (Sensor)   │     │   (Weather)  │     │   Logic     │
└─────────────┘     └──────────────┘     └─────────────┘
                                                 │
                     ┌──────────────┐            │
                     │   Check      │◀───────────┤
                     │  Moisture    │            │
                     └──────────────┘            │
                            │                    │
                     ┌──────┴──────┐              │
                     │  Run Pump? │──────────────┘
                     └────────────┘
```

**Conditions for Auto-Irrigation:**
1. Rain sensor = NOT raining
2. Soil moisture < threshold (e.g., 30%)
3. Weather forecast rain probability < threshold (e.g., 60%)

---

## Part 6: Technology Stack

### ESP32 Firmware
| Component | Technology |
|-----------|------------|
| Framework | Arduino |
| WiFi | WiFi.h |
| MQTT | PubSubClient |
| JSON | ArduinoJson |
| Sensors | DHT, analog input |

### Flutter App
| Component | Technology |
|-----------|------------|
| Framework | Flutter 3.x |
| Language | Dart |
| State | Provider |
| Navigation | GoRouter |
| Backend | Supabase Flutter SDK |
| MQTT | MQTTtx |
| Charts | FL Chart |
| Storage | SharedPreferences |

### Backend
| Component | Technology |
|-----------|------------|
| Database | PostgreSQL (Supabase) |
| Auth | Supabase Auth |
| Realtime | Supabase Realtime |
| Functions | Deno Edge Functions |
| MQTT Broker | HiveMQ Cloud |
| Weather API | Open-Meteo |
| Plant API | Perenual |

---

## Part 7: Security Considerations

### Secrets Management

| Secret | Location | Notes |
|--------|----------|-------|
| WiFi Password | `esp32/config.h` | Stored on device |
| Supabase Anon Key | `esp32/config.h` | Public-safe, RLS protected |
| MQTT Password | `esp32/config.h` | Device credentials |
| FCM Service Account | Supabase Secrets | Edge function only |

### Row Level Security (RLS)
- Users can only see their own devices
- Devices can only write to their own sensor readings
- Crop profiles scoped to user via device ownership

---

## Part 8: Build & Deployment

### ESP32
1. Install Arduino IDE with ESP32 board support
2. Configure credentials in `config.h`
3. Upload via USB/serial

### Flutter App
```bash
cd app
flutter pub get
flutter build apk --release  # Android
flutter build ios --release   # iOS
```

### Supabase
1. Create project at supabase.com
2. Run migrations in SQL Editor
3. Deploy edge functions:
```bash
supabase functions deploy perenual-lookup
supabase functions deploy weekly-summary
supabase functions deploy purge-old-logs
supabase functions deploy send-alert-notification
```

---

## Appendix: Complete File Checklist

### ESP32 Files (5 files)
- [x] `esp32.ino` - Main firmware (164 lines)
- [x] `config.h` - Credentials & pins
- [x] `config.h.example` - Template for config.h
- [x] `supabase_client.h` - API client
- [x] `weather_client.h` - Weather API

### Flutter Files (35 Dart files)
- [x] `main.dart` - Entry point
- [x] `router.dart` - Navigation
- [x] `theme.dart` - Styling
- [x] `app_state_provider.dart` - State (564 lines)
- [x] 15 screens
- [x] 2 services
- [x] 9 widgets
- [x] 3 utils

### Configuration Files
- [x] `app/pubspec.yaml` - Flutter dependencies
- [x] `app/analysis_options.yaml` - Dart analyzer config
- [x] `app/devtools_options.yaml` - DevTools config
- [x] `app/.env.example` - Environment variables template
- [x] `app/.metadata` - Flutter project metadata
- [x] `.vscode/settings.json` - VS Code settings

### Supabase Files
- [x] 3 migrations
- [x] 4 edge functions

### Documentation Files
- [x] `project-architecture.md` - This file
- [x] `edge-functions.md` - Edge functions reference
- [x] `Hardware Components for Smart Irrigation.md` - Hardware guide
- [x] `SISSv2_Architecture_and_Steps.md` - Original architecture
- [x] `Features list.md` - Feature list
- [x] `README.md` - Project readme

### Assets
- [x] Fonts (Manrope, Material Icons)
- [x] App icons
- [x] Lottie animations (weather)
- [x] Weather icon sets (set-1 through set-6)
- [x] Weather icons JSON

---

## Project Statistics

| Category | Count |
|----------|-------|
| Total Dart Files | 35 |
| Total Screens | 15 |
| Total Edge Functions | 4 |
| Total Database Migrations | 3 |
| Total Asset Files | 741+ |
| Documentation Files | 6 |
| ESP32 Source Files | 5 |
