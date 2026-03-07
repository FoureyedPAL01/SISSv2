# SISF Application Settings: Feature and Implementation Specification

The Settings page serves as the centralized configuration hub for user identity, localized preferences, real-time alerting, hardware monitoring, and session management within the SISF application. 

A foundational architectural feature of this page is the **auto-save mechanism**. The interface operates without manual submission buttons for standard configurations; interactions such as toggling a switch or losing focus on an input field trigger immediate, asynchronous state updates to the backend.

## 1. Profile Management
This section handles the user's basic account identification:
* **Username:** An editable text input field utilized for personalizing the user's display name.
* **Email:** A read-only text field displaying the address bound to the account. This acts as the primary unique identifier and the destination for system-generated reports.

## 2. Localization Preferences
This module allows users to adapt environmental data outputs to their regional standards via boolean toggle switches:
* **Temperature Units:** Toggles the global system display between Celsius (°C) and Fahrenheit (°F).
* **Volume Units:** Toggles the global water volume calculations between Litres (L) and Gallons.

## 3. Granular Notification Control
The application features a comprehensive event-driven alert system. Users manage these via independent toggle switches, allowing granular opt-in/opt-out control over specific system triggers:
* **Pump Alerts:** Hardware monitoring that fires notifications upon unexpected pump starts or stops.
* **Soil Moisture Alerts:** Environmental threshold monitoring that triggers when moisture levels hit critical highs or lows.
* **Weather Alerts:** Logic-based notifications linked to rain detection and predictive forecast-based irrigation skips.
* **Fertigation Reminders:** Time-sensitive scheduling alerts preceding automated nutrient injections.
* **Device Offline Alerts:** Connectivity monitoring that alerts the user if the primary hardware node drops off the network.
* **Weekly Summary Report:** An aggregate reporting feature that, when enabled, triggers a server-side cron job to compile and email a digest of water usage and system efficiency.

## 4. Security
Dedicated to credential maintenance:
* **Change Password:** Unlike the auto-save fields, this utilizes an explicit "Update" action trigger, separating sensitive authentication mutations from standard system preferences.

## 5. Device Control and System Health


[Image of IoT system architecture diagram]

This section provides a real-time health dashboard for the integrated hardware and backend infrastructure:

| Component | Implementation Detail |
| :--- | :--- |
| **Primary Device** | Monitors the connection state of the main hardware node (**ESP32-001 Main Field Node**). It actively displays the current network status (e.g., "Online"). |
| **API Connectivity** | Validates the external integration links. It monitors the connection to **Supabase** (likely handling database and authentication) and **Open-Meteo** (supplying the weather forecast data), displaying a "Connected" state when healthy. |

*Note: These statuses likely rely on active polling or WebSockets to reflect real-time system health.*

## 6. Account Lifecycle Management
Located at the bottom of the interface, this section handles high-stakes session and data actions:
* **Sign Out:** An action button that invalidates the current authentication token and terminates the active session.
* **Delete Account:** A highly destructive action button that triggers the complete erasure of the user's account and associated data from the database.

---

## Global Navigation Infrastructure
The Settings view is anchored by a persistent bottom navigation bar, which facilitates routing across the application's core modules:
1. **Dashboard:** The primary monitoring interface.
2. **Analytics:** The historical data and charting view.
3. **Alerts:** An event log view. This tab features a dynamic numerical badge (currently displaying a count of 3) driven by a state manager to indicate unacknowledged system events.
4. **Settings:** The currently active configuration view.
