```
┌─────────────────────────────────────────────────────────────┐
│                    MOBILE APPLICATION                       │
│                        (Flutter)                            │
│  ┌─────────────────┐         ┌────────────────────────────┐│
│  │   Flutter UI    │◄───────►│   Supabase                  ││
│  │   (Dart)        │         │   (Auth, Realtime, DB)      ││
│  └────────┬────────┘         └────────────────────────────┘│
│           │ MQTT/HTTP                                      │
│           ▼                                                 │
│  ┌─────────────────┐                                       │
│  │  Python Backend │◄───────────── (Sensor Data)           │
│  │  (MQTT Broker)  │                                       │
│  └────────┬────────┘                                       │
└───────────┼─────────────────────────────────────────────────┘
            │ MQTT / HTTP
            ▼
┌─────────────────────────────────────────────────────────────┐
│                      CLOUD LAYER                            │
│  ┌─────────────────┐         ┌────────────────────────────┐│
│  │   Python API    │◄───────►│   Supabase                  ││
│  │   (MQTT/Flask)  │         │   (PostgreSQL, Auth,        ││
│  │                 │         │    Realtime, Storage)       ││
│  └─────────────────┘         └────────────────────────────┘│
└────────────────────────────┬────────────────────────────────┘
                             │ MQTT / HTTP
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                    ESP32 FIRMWARE                           │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
│  │  Sensors │  │  Pump    │  │  Relay   │  │   WiFi    │  │
│  │  (DHT,   │──│  Control │──│  Driver  │──│  Module   │  │
│  │  Soil,   │  │          │  │          │  │          │  │
│  │  Rain,   │  │          │  │          │  │          │  │
│  │  Flow)   │  │          │  │          │  │          │  │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Data Flow

| Flow | Connection | Description |
|------|------------|-------------|
| ESP32 → Python | MQTT/HTTP | Sensor data upload (soil moisture, temp, humidity, rain, flow) |
| Python → Supabase | REST API | Store validated sensor data, pump logs, water usage |
| Flutter ↔ Supabase | Direct | Auth, user profiles, real-time subscriptions, historical data |
| Flutter → Python | MQTT/HTTP | Manual pump control, threshold updates, crop profile changes |
| Python → ESP32 | MQTT | Forward control commands from app to ESP32 |

## Key Components

### ESP32 Firmware
- Reads sensors: Soil Moisture, DHT11 (temp/humidity), Rain Sensor, Flow Sensor (YF-S201)
- Publishes sensor data via MQTT to Python backend
- Subscribes to MQTT topics for pump control commands
- Implements automatic irrigation logic based on thresholds

### Python Backend
- MQTT Broker (HiveMQ/Mosquitto) for device communication
- Flask/FastAPI REST API for HTTP endpoints
- Data validation before writing to Supabase
- Weather API integration (OpenWeatherMap)
- Fault detection logic
- ET calculation (Penman-Monteith/Hargreaves)
- Push notification triggers

### Supabase (Cloud Database)
- PostgreSQL database with RLS
- Authentication (email/password, OAuth)
- Real-time subscriptions for live data
- Row Level Security for multi-user/device isolation

### Flutter App
- Direct Supabase connection for auth & real-time data
- MQTT/WebSocket connection to Python for real-time control
- Dashboard with charts (fl_chart/syncfusion)
- Crop profile management
- Irrigation scheduling & manual control
- Notifications display
