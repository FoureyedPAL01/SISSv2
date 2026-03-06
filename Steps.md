# Ordered Development Steps (Fastest Path)

---

## Phase 1 — Infrastructure Setup (Day 1)

- Create Supabase project, enable Auth, grab API keys
- Set up Python venv, install fastapi, paho-mqtt, supabase-py, httpx
- Init Flutter project, add packages: supabase_flutter, fl_chart, mqtt_client, provider
- Install & run local Mosquitto MQTT broker (or use HiveMQ Cloud free tier)

---

## Phase 2 — Database Schema (Day 1–2)

1. Create tables: users, devices, sensor_readings, pump_logs, crop_profiles, irrigation_schedules
2. Enable Row Level Security on all tables + write policies
3. Enable Supabase Realtime on sensor_readings and pump_logs

---

## Phase 3 — ESP32 Firmware (Day 2–3)

1. WiFi + MQTT connect boilerplate
2. Sensor read loop: soil moisture (ADC), DHT11, rain sensor (digital), flow meter (interrupt counter)
3. MQTT publish sensor JSON every 30s to devices/{id}/sensors
4. Subscribe to devices/{id}/control for pump ON/OFF commands
5. Implement local threshold logic as fallback (no WiFi)

---

## Phase 4 — Python Backend (Day 3–5)

1. FastAPI app with /health endpoint
2. MQTT subscriber: validate + insert sensor data into Supabase
3. Weather API integration (OpenWeatherMap) — check forecast before irrigation
4. Irrigation decision engine: soil moisture + weather + ET (Hargreaves equation)
5. Pump control publisher: send MQTT command + log to pump_logs
6. Fault detection: stuck sensor values, pump on with no moisture change, WiFi timeout
7. Push notification trigger (via Supabase Edge Function or FCM)

---

## Phase 5 — Flutter App (Day 4–7)

1. Auth screens: Sign up / Login (Supabase Auth direct)
2. Dashboard: real-time sensor cards (Supabase Realtime subscription)
3. Charts: 24h moisture/temp/humidity history (fl_chart)
4. Manual pump control: toggle button → HTTP POST to Python backend
5. Crop profile selector: Wheat/Rice/Tomato → updates thresholds in Supabase
6. Water usage log screen + irrigation efficiency score display
7. Notification screen: pump events, alerts, fertilizer reminders

---

## Phase 6 — Integration & Polish (Day 7–8)

1. End-to-end test: ESP32 → MQTT → Python → Supabase → Flutter
2. Tune RLS policies, test multi-device isolation
3. Wire up FCM push notifications
4. Fertigation counter + "Days since fertilized" display

