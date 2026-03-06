# SISS Flutter App - Windows/Screens Documentation

## Overview

The SISS (Smart Irrigation System) Flutter application consists of **10 main windows/screens** that provide complete control and monitoring capabilities for the smart irrigation system. The app is built using **Clean Architecture** with **Provider** for state management and **GoRouter** for navigation.

## Project Information

| Attribute | Value |
|-----------|-------|
| **Framework** | Flutter |
| **Language** | Dart |
| **State Management** | Provider |
| **Navigation** | GoRouter |
| **Backend** | Supabase (Database & Auth) + Python FastAPI |
| **Design System** | Material Design 3 |
| **Theme Color** | Green (#16A34A) - Agriculture theme |

---

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| supabase_flutter | ^2.12.0 | Backend database, authentication, realtime subscriptions |
| fl_chart | ^1.1.1 | Data visualization (charts) |
| mqtt_client | ^10.2.1 | IoT MQTT communication |
| provider | ^6.1.5+1 | App-wide state management |
| go_router | ^17.1.0 | Declarative routing with auth redirects |
| phosphor_flutter | ^2.1.0 | Modern icon library |
| flutter_dotenv | ^6.0.0 | Environment variable management |
| http | ^1.6.0 | HTTP requests to Python backend |

---

## All Screens/Windows

| # | Window Name | File Path | Route | Purpose |
|---|-------------|-----------|-------|---------|
| 1 | Login Screen | `lib/screens/login_screen.dart` | `/login` | User authentication (Sign In/Sign Up) |
| 2 | Dashboard Screen | `lib/screens/dashboard_screen.dart` | `/` | Real-time sensor data display |
| 3 | Irrigation Screen | `lib/screens/irrigation_screen.dart` | `/irrigation` | Historical soil moisture trends |
| 4 | Weather Screen | `lib/screens/weather_screen.dart` | `/weather` | Weather forecast from Open-Meteo |
| 5 | Pump Control Screen | `lib/screens/pump_control_screen.dart` | `/pump` | Manual pump ON/OFF control |
| 6 | Crop Profiles Screen | `lib/screens/crop_profiles_screen.dart` | `/crops` | Soil moisture threshold configuration |
| 7 | Water Usage Screen | `lib/screens/water_usage_screen.dart` | `/water` | Weekly water consumption chart |
| 8 | Fertigation Screen | `lib/screens/fertigation_screen.dart` | `/fertigation` | Nutrient application tracking |
| 9 | Alerts Screen | `lib/screens/alerts_screen.dart` | `/alerts` | System alerts (realtime) |
| 10 | Settings Screen | `lib/screens/settings_screen.dart` | `/settings` | User account & device configuration |

---

## Detailed Screen Documentation

---

### 1. Login Screen

| Attribute | Details |
|-----------|---------|
| **File** | `lib/screens/login_screen.dart` |
| **Route** | `/login` |
| **Lines of Code** | 211 |
| **Type** | StatefulWidget |

#### Features

- **Tab-based interface** with two tabs: Sign In and Sign Up
- **Email/Password authentication** via Supabase Auth
- **Error handling** with inline error messages
- **Loading states** with progress indicator during authentication
- **Email confirmation support** - handles scenarios where email confirmation is required

#### UI Components

- App logo (water drop icon)
- Tab bar for Sign In/Sign Up switching
- Email TextField with email keyboard
- Password TextField with obscured text
- Error message container (red background)
- FilledButton for form submission

#### Key Functions

| Function | Description |
|----------|-------------|
| `_signIn()` | Authenticates user with email/password |
| `_signUp()` | Creates new user account |
| `_buildForm()` | Reusable form builder for both tabs |

#### Data Flow

```
User Input → Supabase Auth → Session Created → GoRouter Redirects to '/'
```

---

### 2. Dashboard Screen

| Attribute | Details |
|-----------|---------|
| **File** | `lib/screens/dashboard_screen.dart` |
| **Route** | `/` (Home) |
| **Lines of Code** | 162 |
| **Type** | StatelessWidget (uses Consumer) |

#### Features

- **Real-time sensor data display** via Supabase Realtime subscriptions
- **Grid layout** showing 4 key metrics
- **Recent pump activity timeline** (hardcoded display)
- **Pull-to-refresh** support
- **Device status indicator**

#### Displayed Metrics

| Metric | Unit | Icon | Color |
|--------|------|------|-------|
| Soil Moisture | % | Drop icon | Blue |
| Temperature | °C | Thermometer icon | Orange |
| Humidity | % | Cloud icon | Light Blue |
| Rain Status | - | Sun/Cloud-Rain | Amber/Indigo |

#### Key Components

| Component | Description |
|-----------|-------------|
| `_StatCard` | Reusable card widget for displaying metric data |
| GridView.count | 2x2 grid layout for 4 stat cards |
| ListView | Scrollable list with pump activity timeline |

#### Data Source

- Provider: `AppStateProvider` (Consumer)
- Real-time updates from `sensor_readings` table in Supabase

---

### 3. Irrigation Screen

| Attribute | Details |
|-----------|---------|
| **File** | `lib/screens/irrigation_screen.dart` |
| **Route** | `/irrigation` |
| **Lines of Code** | 262 |
| **Type** | StatefulWidget |

#### Features

- **Historical soil moisture data** visualization (7-day trend)
- **Line chart** using fl_chart library
- **Pull-to-refresh** functionality
- **Empty state handling** for new devices
- **Error state handling** for failed data fetches

#### Data Query

```dart
// Query: sensor_readings table
- device_id: From provider
- time range: Past 7 days
- fields: soil_moisture, created_at
- limit: 200 rows
- order: created_at ASC
```

#### Chart Specifications

| Property | Value |
|----------|-------|
| Type | LineChart |
| X-axis | Days (Mon-Sun) |
| Y-axis | Soil Moisture % (0-100) |
| Color | Green (#16A34A) |
| Data Points | Max 200 |
| Interpolation | Curved |

#### Key Functions

| Function | Description |
|----------|-------------|
| `_fetchHistory()` | Fetches 7-day historical data from Supabase |
| `_buildChartBody()` | Handles loading, error, empty, and data states |

---

### 4. Weather Screen

| Attribute | Details |
|-----------|---------|
| **File** | `lib/screens/weather_screen.dart` |
| **Route** | `/weather` |
| **Lines of Code** | 330 |
| **Type** | StatefulWidget |

#### Features

- **Current weather conditions** from Open-Meteo API (free, no API key required)
- **7-day forecast display**
- **Rain warning banner** (when rain probability > 50%)
- **Pull-to-refresh** functionality
- **Error handling** with retry button

#### Location Configuration

```dart
static const double _lat = 19.097092385037833;  // Mumbai area
static const double _lon = 72.89634431557758;
```

#### API Endpoint

```
https://api.open-meteo.com/v1/forecast
?latitude=19.097
&longitude=72.896
&current=temperature_2m,relative_humidity_2m,precipitation,weather_code,wind_speed_10m
&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max,weather_code
&timezone=auto
&forecast_days=7
```

#### Displayed Weather Data

| Data | Description |
|------|-------------|
| Current Temperature | Real-time temperature in °C |
| Weather Condition | Clear, Cloudy, Rainy, etc. (WMO codes) |
| Humidity | Current relative humidity % |
| Wind Speed | Current wind speed in km/h |
| Rain Probability | Today's precipitation probability % |
| 7-Day Forecast | Daily max/min temps and rain chances |

#### Key Functions

| Function | Description |
|----------|-------------|
| `_fetchWeather()` | Fetches weather from Open-Meteo API |
| `_parseResponse()` | Parses raw API JSON into app data |
| `_weatherLabel()` | Converts WMO code to human-readable label |
| `_weatherIcon()` | Maps WMO code to Phosphor icon |

---

### 5. Pump Control Screen

| Attribute | Details |
|-----------|---------|
| **File** | `lib/screens/pump_control_screen.dart` |
| **Route** | `/pump` |
| **Lines of Code** | 90 |
| **Type** | StatefulWidget |

#### Features

- **Manual pump control** - Turn ON/OFF
- **HTTP POST request** to Python backend
- **Loading state** during command execution
- **Snackbar feedback** for success/failure

#### Backend Communication

```
Endpoint: POST {PYTHON_BACKEND_URL}/api/pump/toggle
Headers: Content-Type: application/json
Body: {
  "device_id": "esp32_01",
  "command": "pump_on" | "pump_off"
}
```

#### UI Components

| Button | Icon | Action | Style |
|--------|------|--------|-------|
| Turn Pump ON | water_drop | Sends `pump_on` command | FilledButton (green) |
| Turn Pump OFF | stop_circle | Sends `pump_off` command | FilledButton (red) |

#### Error Handling

- Network errors displayed via SnackBar
- Server errors (non-200 status codes) displayed with status code
- Connection timeout handling

---

### 6. Crop Profiles Screen

| Attribute | Details |
|-----------|---------|
| **File** | `lib/screens/crop_profiles_screen.dart` |
| **Route** | `/crops` |
| **Lines of Code** | 164 |
| **Type** | StatefulWidget |

#### Features

- **Soil moisture threshold configuration**
- **Slider input** for dry threshold (0-100%)
- **Data persistence** to Supabase crop_profiles table
- **Device-crop profile linking**
- **Loading and error states**

#### Database Operations

1. **Fetch**: Get current crop profile from `devices` table with join to `crop_profiles`
2. **Upsert**: Insert/update crop profile in `crop_profiles` table
3. **Update**: Link device to crop profile in `devices` table

#### Threshold Configuration

| Parameter | Range | Default | Description |
|-----------|-------|---------|-------------|
| Dry Threshold | 0-100% | 30% | Minimum soil moisture - pump turns on below this |

#### Key Functions

| Function | Description |
|----------|-------------|
| `_fetchCurrentProfile()` | Loads existing crop profile from database |
| `_saveSettings()` | Saves threshold to Supabase |

---

### 7. Water Usage Screen

| Attribute | Details |
|-----------|---------|
| **File** | `lib/screens/water_usage_screen.dart` |
| **Route** | `/water` |
| **Lines of Code** | 85 |
| **Type** | StatelessWidget |

#### Features

- **Weekly water consumption chart**
- **Line chart** using fl_chart
- **Total consumption display**
- **Currently uses mock data** (not yet integrated with real backend)

#### Chart Data (Mock)

```dart
final List<FlSpot> spots = [
  const FlSpot(1, 12),  // Monday: 12L
  const FlSpot(2, 18),  // Tuesday: 18L
  const FlSpot(3, 15),  // Wednesday: 15L
  const FlSpot(4, 25),  // Thursday: 25L
  const FlSpot(5, 14),  // Friday: 14L
  const FlSpot(6, 30),  // Saturday: 30L
  const FlSpot(7, 22),  // Sunday: 22L
];
// Total: 136L
```

#### Display Metrics

| Metric | Value |
|--------|-------|
| Weekly Trend | Line chart visualization |
| Total Consumption | 136L (hardcoded) |

#### Implementation Note

> **Status**: Mock data implementation
> 
> **Future Enhancement**: Aggregate data from `pump_logs` table in Supabase to calculate actual water usage based on flow meter readings.

---

### 8. Fertigation Screen

| Attribute | Details |
|-----------|---------|
| **File** | `lib/screens/fertigation_screen.dart` |
| **Route** | `/fertigation` |
| **Lines of Code** | 68 |
| **Type** | StatelessWidget |

#### Features

- **Nutrient application tracking**
- **Nutrition status display** (Good/Poor)
- **Days since last application**
- **Next scheduled application** countdown
- **Log fertilizer button** (placeholder)

#### Displayed Information

| Field | Value |
|-------|-------|
| Nutrition Status | "Good" (hardcoded) |
| Days Since Last Application | "12 Days" (hardcoded) |
| Next Scheduled Application | "In 2 Days" (hardcoded) |

#### UI Components

| Component | Description |
|-----------|-------------|
| Card | Container for nutrition status |
| Row | Status icon and label |
| ListTile | Days since / Next application info |
| FilledButton | "Log Fertilizer Application" button |

#### Implementation Note

> **Status**: Basic UI with hardcoded data
> 
> **Future Enhancement**: 
> - Create `fertigation_logs` table in Supabase
> - Implement actual fertilizer logging functionality
> - Calculate days since last application from database

---

### 9. Alerts Screen

| Attribute | Details |
|-----------|---------|
| **File** | `lib/screens/alerts_screen.dart` |
| **Route** | `/alerts` |
| **Lines of Code** | 65 |
| **Type** | StatelessWidget |

#### Features

- **Real-time system alerts** via Supabase Realtime
- **Stream-based updates** from `system_alerts` table
- **Alert status display** (Active/Resolved)
- **Empty state** when no alerts exist
- **Auto-refresh** on new alerts

#### Data Source

```dart
// Supabase Realtime stream
Supabase.instance.client
  .from('system_alerts')
  .stream(primaryKey: ['id'])
  .order('created_at', ascending: false)
  .limit(20);
```

#### Alert Display

| Field | Source |
|-------|--------|
| Alert Type | `alert_type` column |
| Message | `message` column |
| Status | `status` column (active/resolved) |

#### Alert States

| Status | Chip Color |
|--------|------------|
| Active | Red |
| Resolved | Default (gray) |

#### Empty State

- Check icon (green)
- Message: "No active alerts! System is running smoothly."

---

### 10. Settings Screen

| Attribute | Details |
|-----------|---------|
| **File** | `lib/screens/settings_screen.dart` |
| **Route** | `/settings` |
| **Lines of Code** | 72 |
| **Type** | StatelessWidget |

#### Features

- **User account information** display
- **Device configuration** link (placeholder)
- **Notifications settings** link (placeholder)
- **General settings** link (placeholder)
- **Sign out functionality**

#### User Information

| Field | Source |
|-------|--------|
| Account Email | `Supabase.instance.client.auth.currentUser?.email` |

#### Menu Items

| Item | Icon | Status |
|------|------|--------|
| Account | user | Displays user email |
| Device Configuration | deviceMobile | Placeholder (tap does nothing) |
| Notifications | bell | Placeholder (tap does nothing) |
| Settings | gear | Placeholder (tap does nothing) |

#### Sign Out

- FilledButton with red foreground color
- Calls `AppStateProvider.signOut()` method
- Triggers GoRouter redirect to login page

---

## Navigation Structure

### Routes Configuration

| Route | Screen | Auth Required |
|-------|--------|--------------|
| `/login` | LoginScreen | No |
| `/` | DashboardScreen | Yes |
| `/irrigation` | IrrigationScreen | Yes |
| `/weather` | WeatherScreen | Yes |
| `/pump` | PumpControlScreen | Yes |
| `/crops` | CropProfilesScreen | Yes |
| `/water` | WaterUsageScreen | Yes |
| `/fertigation` | FertigationScreen | Yes |
| `/alerts` | AlertsScreen | Yes |
| `/settings` | SettingsScreen | Yes |

### Navigation Components

- **GoRouter** - Declarative routing with auth-based redirects
- **ShellRoute** - Bottom navigation bar wrapper
- **Material 3 NavigationBar** - Main navigation
- **NavigationDrawer** - Side drawer alternative

---

## State Management

### AppStateProvider

| Property | Type | Description |
|----------|------|-------------|
| `isLoading` | bool | Loading state for initial data fetch |
| `deviceId` | String? | Current user's device ID |
| `latestSensorData` | Map | Most recent sensor readings |
| `user` | User? | Supabase authenticated user |

### Methods

| Method | Description |
|--------|-------------|
| `signOut()` | Signs out user and redirects to login |
| Real-time subscriptions | Listens to sensor_readings table |

---

## API Integration

### Supabase Tables Used

| Table | Operations | Description |
|-------|------------|-------------|
| `devices` | SELECT, UPDATE | Device information and crop profile links |
| `sensor_readings` | SELECT, INSERT (via ESP32) | Sensor data storage |
| `crop_profiles` | SELECT, UPSERT | Crop moisture thresholds |
| `pump_logs` | INSERT (via backend) | Pump action logging |
| `system_alerts` | SELECT, STREAM | System alert storage |

### Python Backend API

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/pump/toggle` | POST | Manual pump control |
| `/api/weather/current` | GET | Weather data (optional) |

### External APIs

| API | Purpose | Auth Required |
|-----|---------|---------------|
| Open-Meteo | Weather forecast | No (free API) |

---

## Implementation Status Summary

| Screen | Status | Notes |
|--------|--------|-------|
| Login | ✅ Complete | Full authentication |
| Dashboard | ✅ Complete | Real-time sensor data |
| Irrigation | ✅ Complete | Historical chart |
| Weather | ✅ Complete | Open-Meteo integration |
| Pump Control | ✅ Complete | Backend API integration |
| Crop Profiles | ✅ Complete | Threshold configuration |
| Water Usage | ⚠️ Partial | Mock data only |
| Fertigation | ⚠️ Partial | Hardcoded data |
| Alerts | ✅ Complete | Realtime updates |
| Settings | ⚠️ Partial | Placeholder items |

---

## File Structure

```
lib/
├── main.dart                 # App entry point
├── router.dart              # GoRouter configuration
├── theme.dart               # Material 3 theme
├── providers/
│   └── app_state_provider.dart  # State management
└── screens/
    ├── login_screen.dart        # Screen 1
    ├── dashboard_screen.dart   # Screen 2
    ├── irrigation_screen.dart   # Screen 3
    ├── weather_screen.dart      # Screen 4
    ├── pump_control_screen.dart # Screen 5
    ├── crop_profiles_screen.dart# Screen 6
    ├── water_usage_screen.dart  # Screen 7
    ├── fertigation_screen.dart  # Screen 8
    ├── alerts_screen.dart       # Screen 9
    └── settings_screen.dart     # Screen 10
```

---

## Environment Configuration (.env)

```bash
SUPABASE_URL=https://qflazwitypjqutgbojqk.supabase.co
SUPABASE_ANON_KEY=<jwt-token>
PYTHON_BACKEND_URL=http://192.168.0.107:8000
```

---

*Last Updated: 2026-03-01*
*Project: SISS (Smart Irrigation System)*
