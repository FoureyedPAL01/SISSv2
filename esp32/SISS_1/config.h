// config.h
// All credentials, pin assignments, and tunable constants live here.
// Edit this file only — SISS_1.ino should not need changes for a new device.

#ifndef CONFIG_H
#define CONFIG_H

// ─── WiFi ────────────────────────────────────────────────────────────────────
#define WIFI_SSID   "RTP #4"
#define WIFI_PASS   "$avine597"

// ─── MQTT Broker ─────────────────────────────────────────────────────────────
// Use your PC's local IP if running Mosquitto locally (e.g. 192.168.1.10)
#define MQTT_BROKER "192.168.0.104"
#define MQTT_PORT   1883
#define MQTT_USER   ""
#define MQTT_PASS   ""

// ─── Device Identity ─────────────────────────────────────────────────────────
#define DEVICE_ID   "esp32_01"

// ─── MQTT Topics ─────────────────────────────────────────────────────────────
#define TOPIC_SENSORS  "devices/" DEVICE_ID "/sensors"
#define TOPIC_CONTROL  "devices/" DEVICE_ID "/control"

// ─── GPIO Pins ───────────────────────────────────────────────────────────────
// Verified against ESP32 DOIT DevKit V1 30-pin diagram
// USB at bottom, pin 1 = bottom, pin 15 = top
#define PIN_SOIL        34   // Analog input:   soil moisture AOUT — left side pin 12
#define PIN_DHT          4   // Digital input:  DHT11 DATA       — right side pin 5
#define PIN_RAIN        35   // Digital input:  rain sensor DO   — left side pin 11
#define PIN_FLOW        18   // Digital input:  YF-S201 signal   — right side pin 9
#define PIN_PUMP_RELAY  26   // Digital output: MOSFET/relay IN  — left side pin 7

// ─── Pump Switch Polarity ────────────────────────────────────────────────────
// IRF520 MOSFET: active-HIGH → HIGH turns pump ON  → RELAY_ACTIVE_LOW false
// Relay module:  active-LOW  → LOW  turns pump ON  → RELAY_ACTIVE_LOW true
// Set according to whichever module you are using
#define RELAY_ACTIVE_LOW  false   // false = MOSFET | true = relay

#define PUMP_ON   (RELAY_ACTIVE_LOW ? LOW  : HIGH)
#define PUMP_OFF  (RELAY_ACTIVE_LOW ? HIGH : LOW)

// ─── Soil Moisture Calibration ───────────────────────────────────────────────
// Step 1: hold sensor in open air → note Serial Monitor raw value → SOIL_DRY_RAW
// Step 2: dip sensor tip in water → note Serial Monitor raw value → SOIL_WET_RAW
#define SOIL_DRY_RAW  3200   // replace with your calibrated dry reading
#define SOIL_WET_RAW  1200   // replace with your calibrated wet reading

// ─── Default Irrigation Thresholds ───────────────────────────────────────────
// Used on first boot — overridden by app via MQTT set_threshold command
// Saved to NVS so they survive power cuts
#define DEFAULT_DRY_THRESHOLD  30.0f   // % — below this, turn pump on
#define DEFAULT_WET_THRESHOLD  70.0f   // % — above this, turn pump off

// ─── Timing ──────────────────────────────────────────────────────────────────
#define SENSOR_READ_INTERVAL   2000          // ms — DHT11 minimum is 2000ms
#define PUBLISH_INTERVAL       30000         // ms — publish to MQTT every 30s
#define MQTT_RETRY_INTERVAL    5000          // ms — non-blocking reconnect wait
#define MAX_PUMP_RUNTIME       (30 * 60000)  // ms — force pump off after 30 min
#define WDT_TIMEOUT_SEC        30            // s  — watchdog reboot if loop hangs

#endif
