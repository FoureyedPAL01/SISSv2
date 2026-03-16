# SISS v2 - Smart Irrigation & Sensor System

A serverless IoT irrigation system using Flutter (mobile app), ESP32 (firmware), and Supabase (backend).

## Project Structure

```
SISSv2/
├── app/                    # Flutter mobile application
│   ├── lib/                # Dart source code
│   ├── supabase/           # Supabase Edge Functions & migrations
│   ├── .env.example        # Environment variables template
│   └── pubspec.yaml        # Flutter dependencies
├── esp32/                  # ESP32 firmware
│   ├── config.h.example    # Configuration template
│   ├── main.ino            # Main firmware
│   └── *.h                 # Header files
└── supabase/               # Supabase project files (local config)
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
OPENWEATHER_API_KEY=your-api-key
```

Run the app:

```bash
flutter run
```

### 2. ESP32 Firmware Setup

Copy the configuration template:

```bash
cd esp32
cp config.h.example config.h
```

Edit `config.h` with your credentials:

- WiFi SSID & Password
- Supabase URL & Anon Key
- Device UUID (from Supabase devices table)
- HiveMQ Cloud credentials
- GPS coordinates for weather

Flash to ESP32 using Arduino IDE or PlatformIO.

### 3. Supabase Setup

1. Create a new Supabase project
2. Run migrations in `app/supabase/migrations/`
3. Deploy edge functions in `app/supabase/functions/`
4. Create a device entry in the `devices` table

## Features

- Real-time sensor monitoring (soil moisture, temperature, humidity, flow rate)
- Manual pump control via MQTT
- Automated irrigation based on crop profiles
- Weather integration (Open-Meteo API)
- Alert system for sensor anomalies
- 7-day weather forecast

## Tech Stack

| Component | Technology |
|-----------|------------|
| Mobile App | Flutter + Provider |
| Backend | Supabase (PostgreSQL + Edge Functions) |
| MQTT Broker | HiveMQ Cloud |
| Firmware | ESP32 (Arduino) |
| Weather Data | Open-Meteo API |

## License

MIT License
