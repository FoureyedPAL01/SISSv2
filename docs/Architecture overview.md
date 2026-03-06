## Architecture Overview

```
ESP32 (WiFi) → Python Backend → Supabase (PostgreSQL)
                      ↕              ↕
                Flutter App ←→ Supabase (direct)
```

## How Each Component Works Together

### 1. **User Authentication & Information**
- **Flutter ↔ Supabase:** Direct connection using `supabase_flutter` package
- User signs up/logs in directly from the app
- Supabase handles authentication, JWT tokens, password reset automatically
- User profiles stored in Supabase `users` table

### 2. **Sensor Data Storage**
- ESP32 → Python → Supabase
- ESP32 sends MQTT messages or HTTP POST to Python backend
- Python validates data and writes to Supabase using `supabase-py` library
- More secure, you control data validation

### 3. **Real-time Charts & Analysis**
- Flutter queries Supabase directly for historical data
- Supabase has built-in **real-time subscriptions** (like Firebase)
- Charts update automatically when new sensor data arrives
- Use packages like `fl_chart` or `syncfusion_flutter_charts` in Flutter

## Key Supabase Features
✅ **Authentication** - Email/password, OAuth, magic links

✅ **PostgreSQL Database** - Powerful queries, relationships, indexes

✅ **Real-time Subscriptions** - Live data updates to Flutter app

✅ **Row Level Security (RLS)** - Users only see their own devices/data

✅ **Storage** - Store plant photos (optional)

✅ **Edge Functions** - Serverless functions if needed (Python/TypeScript)

✅ **REST API** - Auto-generated from your schema

✅ **Free Tier** - 500MB database, 2GB storage, 50,000 monthly active users
