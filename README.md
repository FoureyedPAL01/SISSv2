# SISS v2 - Smart Irrigation & Sensor System

A serverless IoT irrigation system using Flutter (mobile app), ESP32 (firmware), and Supabase (backend).

## Project Structure

```
SISSv2/
├── app/                    # Flutter mobile application
│   ├── lib/                # Dart source code
│   │   ├── main.dart       # App entry point
│   │   ├── router.dart     # GoRouter navigation
│   │   ├── theme.dart      # App theming
│   │   ├── providers/      # State management (Provider)
│   │   ├── screens/       # 15 UI screens
│   │   ├── services/       # MQTT & Push notifications
│   │   ├── widgets/        # Reusable UI components
│   │   └── utils/          # Helper functions
│   ├── android/            # Android platform files
│   ├── ios/                # iOS platform files
│   ├── assets/             # Fonts, icons, animations
│   ├── supabase/           # Edge Functions & migrations
│   ├── .env.example        # Environment variables template
│   └── pubspec.yaml        # Flutter dependencies
├── esp32/                  # ESP32 firmware
│   ├── config.h            # Configuration (credentials)
│   ├── esp32.ino           # Main firmware
│   ├── supabase_client.h   # REST API client
│   └── weather_client.h    # Open-Meteo API client
├── supabase/               # Supabase project files (local config)
└── docs/                   # Documentation
```

## Prerequisites

- **Flutter SDK** 3.x
- **Supabase** account (Cloud)
- **ESP32** board (DevKit-V1 or similar)
- **Arduino IDE** or **PlatformIO**

## Setup Instructions

### 1. Flutter App Setup

```bash
cd app
flutter pub get
```

Copy the environment template:

```bash
cp .env.example .env
```

Edit `.env` with your credentials:

```
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
HIVEMQ_BROKER=your-broker.xx.hivemq.cloud
HIVEMQ_PORT=8883
HIVEMQ_USERNAME=your-username
HIVEMQ_PASSWORD=your-password
```

Run the app:

```bash
flutter run
```

### 2. ESP32 Firmware Setup

Edit `esp32/config.h` with your credentials:

- WiFi SSID & Password
- Supabase URL & Anon Key
- Device UUID (from Supabase devices table)
- HiveMQ Cloud credentials
- GPS coordinates for weather

Flash to ESP32 using Arduino IDE or PlatformIO.

### 3. Supabase Setup

1. Create a new Supabase project
2. Run migrations in SQL Editor
3. Deploy edge functions:
```bash
supabase functions deploy perenual-lookup
supabase functions deploy weekly-summary
supabase functions deploy purge-old-logs
supabase functions deploy send-alert-notification
```
4. Create a device entry in the `devices` table

## Features

- Real-time sensor monitoring (soil moisture, temperature, humidity, flow rate, rain sensor)
- Manual pump control via MQTT (HiveMQ Cloud)
- Automated irrigation based on crop profiles with weather forecast integration
- Weather integration (Open-Meteo API - free, no API key required)
- Alert system for sensor anomalies and device status
- 7-day weather forecast display
- User authentication (Supabase Auth)
- Push notifications (Firebase Cloud Messaging)

## Tech Stack

| Component | Technology |
|-----------|------------|
| Mobile App | Flutter + Provider + GoRouter |
| Backend | Supabase (PostgreSQL + Auth + Realtime + Edge Functions) |
| MQTT Broker | HiveMQ Cloud |
| Firmware | ESP32 (Arduino) |
| Weather Data | Open-Meteo API |
| Plant Data | Perenual API |
| Push Notifications | Firebase Cloud Messaging |

## Architecture

### Data Flow

**Sensor Data:**
```
ESP32 → Supabase REST → Supabase Realtime → Flutter App (instant update)
```

**Pump Control:**
```
Flutter App → HiveMQ MQTT → ESP32 → Pump Relay
```

**Auto-Irrigation:**
```
ESP32 → Check Soil Moisture → Check Rain Sensor → Check Weather Forecast → Decision
```

## Screens (15)

1. Login - User authentication
2. Dashboard - Main view with sensor data & pump control
3. Device Management - Add/remove ESP32 devices
4. Link Device - Device linking flow
5. Device Choice - Device selection
6. Crop Profiles - Configure irrigation thresholds
7. Irrigation - View irrigation history
8. Water Usage - Water consumption analytics
9. Weather - Weather forecast display
10. Alerts - Device alerts and notifications
11. Fertigation - Fertilizer/plant management
12. Settings - App preferences
13. Preferences - User preferences (units, location)
14. Profile - User profile management
15. More - Additional options

## License

MIT License
