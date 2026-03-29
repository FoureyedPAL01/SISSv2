# RootSync Migration Plan

---

## Phase 1: Firebase Architecture & Backend Setup

Before writing any Kotlin code, we need to set up the new backend infrastructure to replace Supabase.

### 1.1 Project Initialization

* Create a new project in the **Firebase Console**.
* Enable **Authentication** (Email/Password provider to replace Supabase Auth).
* Enable **Firestore Database** (NoSQL).
* Enable **Firebase Cloud Messaging (FCM)** for push notifications.

### 1.2 Firestore NoSQL Schema Design

Unlike PostgreSQL, NoSQL databases duplicate data to optimize for reads. Set up these root collections:

* `users`: Document ID is the Firebase Auth UID. Stores user profile info and preferences (replaces `user_profiles` table).
* `devices`: Stores ESP32 metadata (name, status).
    * *Sub-collection:* `sensor_readings` (Time-series data for moisture, temp, humidity).
    * *Sub-collection:* `pump_logs` (Records of irrigation cycles, water usage).
    * *Sub-collection:* `crop_profiles` (Thresholds specific to the device).

### 1.3 Firebase Cloud Functions (Node.js/TypeScript)

Migrate your 4 Supabase Deno Edge functions to Firebase Cloud Functions:

* `perenual-lookup`: HTTP callable function to fetch and cache plant care API data.
* `weekly-summary`: Pub/Sub scheduled function (runs weekly) to email users.
* `purge-old-logs`: Pub/Sub scheduled function (runs daily) to delete `pump_logs` older than 14 days.
* `send-alert-notification`: Firestore Trigger function (listens for new alerts in a `system_alerts` collection and sends FCM pushes).

---

## Phase 2: Android Project Setup & Core Architecture

Now, let's set up the Kotlin project using modern Android development practices (Jetpack Compose, Coroutines, Flow, and Hilt).

### 2.1 Initial Project Configuration

* Create a new **Empty Compose Activity** project in Android Studio.
* Add Firebase dependencies to your `build.gradle.kts` (Auth, Firestore, Messaging).
* Add architectural dependencies: **Hilt** (Dependency Injection), **Navigation Compose**, **ViewModel**, and **Moshi/Gson** (JSON parsing).

### 2.2 Directory Structure (The Android Way)

Reorganize your `app/lib/` structure into standard Android packages:

```
com.yourdomain.RootSync/
├── di/                          # Hilt Modules (Firebase instances, MQTT clients)
├── data/                        # Replaces supabase/services logic
│   ├── model/                   # Kotlin Data Classes (SensorReading, PumpLog, etc.)
│   ├── repository/              # Logic to fetch from Firestore/MQTT
│   └── remote/                  # Open-Meteo API client using Retrofit
├── domain/                      # Business logic (e.g., Calculate ET, Efficiency Score)
├── ui/                          # Replaces lib/screens and lib/widgets
│   ├── theme/                   # Replaces theme.dart
│   ├── navigation/              # Replaces router.dart
│   ├── screens/                 # Jetpack Compose UI (Dashboard, Settings, etc.)
│   └── components/              # Replaces lib/widgets (Reusable UI elements)
└── util/                        # Replaces lib/utils (Date formatters, Enums)
```

---

## Phase 3: Data Layer & State Management Migration

We need to replace your Flutter `app_state_provider.dart` with Android's `ViewModel` and Kotlin `StateFlow`.

### 3.1 Authentication Repository

* Create `AuthRepository.kt` to handle Firebase Auth login/logout and map the Firebase User to your local `User` data class.

### 3.2 Firestore Repositories

* Create `SensorRepository.kt`: Use Firestore's `addSnapshotListener` to expose a `Flow<List<SensorReading>>`. This replaces Supabase Realtime and will automatically push updates to the UI whenever the ESP32 writes new data.
* Create `DeviceRepository.kt`: Handle fetching device status, adding/removing ESP32s, and fetching/updating `crop_profiles`.

### 3.3 External APIs & MQTT Service

* Create `WeatherRepository.kt` using Retrofit to fetch the Open-Meteo forecast.
* Rebuild `mqtt_service.dart` as an Android Service using the **Eclipse Paho MQTT** Android client to maintain the manual `pump_on` / `pump_off` commands to HiveMQ.

---

## Phase 4: Jetpack Compose UI Implementation (Screen by Screen)

With the data layer providing Kotlin `Flows`, we can build the UI to react to data changes.

### 4.1 The Foundation Screens

* **Theme & Navigation:** Setup `ui/theme` (colors/typography) and `NavHost` for routing.
* **`LoginScreen`:** Build the email/password UI and connect it to `AuthViewModel`.

### 4.2 Core Functionality (The "Main Tab")

* **`DashboardScreen`:** The most important screen. Collect the `StateFlow` from `SensorViewModel` to show real-time moisture, temp, and humidity. Add a button that triggers the MQTT manual pump control.
* **`DeviceChoiceScreen` & `DeviceManagementScreen`:** UI to link/unlink ESP32 UUIDs to the user's Firestore document.

### 4.3 Analytics & Automation Screens

* **`WeatherScreen`:** Display Open-Meteo data. Use the Lottie animation files from your `assets/lottie/` folder.
* **`IrrigationScreen` & `WaterUsageScreen`:** Fetch `pump_logs` from Firestore. Use a library like **Vico** or **YCharts** (replacing FL Chart) to display water consumption analytics.
* **`CropProfilesScreen` & `FertigationScreen`:** Forms to let users select crops and update the Firestore `crop_profiles` thresholds, and view "Days Since Last Fertilized".

### 4.4 Alerts & Settings Screens

* **`AlertsScreen`:** Display historical alerts fetched from Firestore.
* **`ProfileScreen`, `SettingsScreen`, `PreferencesScreen`:** UI for unit conversions and user details.

---

## Phase 5: Background Work & Hardware Syncing

The app needs to handle things even when it's closed.

### 5.1 Push Notifications (FCM)

* Implement `FirebaseMessagingService` in Android to receive alerts (e.g., "Pump ON", "Rain detected").
* Extract the payload and trigger Android System Notifications, allowing the user to tap and deep-link directly to the `AlertsScreen`.

### 5.2 ESP32 Firmware Update

* Modify `esp32.ino` and `config.h`. Replace the `supabase_client.h` logic with the `Firebase-ESP-Client` library.
* Ensure the ESP32 pushes data exactly to the new Firestore schema (`devices/{deviceId}/sensor_readings`).

---

## Phase 6: Testing & QA

### 6.1 Logic Verification

* Write JUnit tests for your view models to ensure the *Irrigation Efficiency Score* and *Evapotranspiration (ET)* logic calculate correctly based on dummy sensor data.

### 6.2 Hardware-in-the-Loop Testing

* Run the Kotlin app on a physical Android device.
* Power up the ESP32 DevKit V1 with the DHT11, soil moisture, and flow sensors attached.
* Verify that dipping the soil sensor in water instantly reflects on the Android Compose Dashboard via Firestore Realtime streams.

---

> This structured approach ensures you build a solid, reactive foundation before diving into UI design.
