// config.h
// All credentials, pin assignments, and tunable constants live here.
// Edit this file only — SISS_1.ino should not need changes for a new device.

#ifndef CONFIG_H
#define CONFIG_H

// ─── WiFi ────────────────────────────────────────────────────────────────────
#define WIFI_SSID   "your_wifi_name"
#define WIFI_PASS   "your_wifi_password"

// ─── MQTT Broker ─────────────────────────────────────────────────────────────
// Use your PC's local IP if running Mosquitto locally (e.g. 192.168.1.10)
// Use HiveMQ Cloud hostname if using cloud broker
#define MQTT_BROKER "192.168.1.10"
#define MQTT_PORT   1883
#define MQTT_USER   ""   // leave blank if broker has no auth
#define MQTT_PASS   ""

// ─── Device Identity ─────────────────────────────────────────────────────────
// Change this per physical device if you deploy multiple ESP32s
#define DEVICE_ID   "esp32_01"

// ─── MQTT Topics ─────────────────────────────────────────────────────────────
#define TOPIC_SENSORS  "devices/" DEVICE_ID "/sensors"
#define TOPIC_CONTROL  "devices/" DEVICE_ID "/control"

// ─── GPIO Pins ───────────────────────────────────────────────────────────────
#define PIN_SOIL        34   // Analog input:    soil moisture sensor AO pin
#define PIN_DHT         4    // Digital input:   DHT11 data pin
#define PIN_RAIN        35   // Digital input:   rain sensor DO pin
#define PIN_FLOW        18   // Digital input:   YF-S201 flow sensor pulse pin
#define PIN_PUMP_RELAY  26   // Digital output:  relay module IN pin

// ─── Relay Polarity ──────────────────────────────────────────────────────────
// HOW TO TEST: Upload firmware, open Serial Monitor.
// Run: mosquitto_pub -t "devices/esp32_01/control" -m '{"cmd":"pump_on"}'
// If pump turns OFF  → your relay is active-LOW → set true
// If pump turns ON   → your relay is active-HIGH → set false
#define RELAY_ACTIVE_LOW  false   // change to true if pump logic is inverted

// Helper macros — use PUMP_ON / PUMP_OFF everywhere instead of HIGH/LOW directly
#define PUMP_ON   (RELAY_ACTIVE_LOW ? LOW  : HIGH)
#define PUMP_OFF  (RELAY_ACTIVE_LOW ? HIGH : LOW)

// ─── Soil Moisture Calibration ───────────────────────────────────────────────
// Read raw ADC values in Serial Monitor:
//   DRY_RAW  = value when sensor is in open air (completely dry)
//   WET_RAW  = value when sensor is submerged in water
// Then set these accordingly.
#define SOIL_DRY_RAW  3200   // typical dry value  (adjust after calibration)
#define SOIL_WET_RAW  1200   // typical wet value  (adjust after calibration)

// ─── Default Irrigation Thresholds ───────────────────────────────────────────
// These are used on first boot and as fallback when no backend command has arrived.
// The app/backend can override these via MQTT set_threshold command.
#define DEFAULT_DRY_THRESHOLD  30.0f   // % — below this, turn pump on
#define DEFAULT_WET_THRESHOLD  70.0f   // % — above this, turn pump off

// ─── Timing ──────────────────────────────────────────────────────────────────
#define SENSOR_READ_INTERVAL   2000          // ms — DHT11 minimum is 2000 ms
#define PUBLISH_INTERVAL       30000         // ms — send data to backend every 30s
#define MQTT_RETRY_INTERVAL    5000          // ms — non-blocking reconnect interval
#define MAX_PUMP_RUNTIME       (30 * 60000)  // ms — force pump off after 30 minutes
#define WDT_TIMEOUT_SEC        30            // seconds — watchdog reboot if loop hangs

#endif
