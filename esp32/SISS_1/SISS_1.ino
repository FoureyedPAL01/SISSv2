#include <WiFi.h>
#include <PubSubClient.h>
#include <DHT.h>
#include <ArduinoJson.h>
#include <Preferences.h>       // ESP32 NVS: survives reboots and power loss
#include <ArduinoOTA.h>        // Over-the-air firmware updates
#include <esp_task_wdt.h>      // Hardware watchdog timer
#include "config.h"

// ─── Objects ─────────────────────────────────────────────────────────────────
WiFiClient   espClient;
PubSubClient mqtt(espClient);
DHT          dht(PIN_DHT, DHT11);
Preferences  prefs;

// ─── Thresholds (loaded from NVS on boot) ────────────────────────────────────
float soilDryThreshold = DEFAULT_DRY_THRESHOLD;
float soilWetThreshold = DEFAULT_WET_THRESHOLD;

// ─── Pump safety tracking ────────────────────────────────────────────────────
// Tracks when the pump was turned on so we can enforce a max runtime.
// 0 means pump is currently off.
uint32_t pumpOnTime = 0;

// ─── Timing ──────────────────────────────────────────────────────────────────
// Note: unsigned subtraction (millis() - lastX) handles the ~49-day
// millis() overflow correctly because uint32_t wraps predictably in C.
// Do NOT change these to signed integers.
uint32_t lastSensorRead = 0;
uint32_t lastPublish    = 0;

// ─── Flow sensor pulse counter ───────────────────────────────────────────────
// volatile: tells the compiler this variable can change outside normal code flow
// (inside an ISR). Without this, the compiler may cache it in a register and
// miss updates.
volatile uint32_t flowPulseCount = 0;

// IRAM_ATTR: places this function in fast IRAM (instruction RAM).
// Required for interrupt handlers on ESP32 — flash reads are too slow for ISRs.
void IRAM_ATTR onFlowPulse() {
  flowPulseCount++;
}

// ─── Sensor data structure ───────────────────────────────────────────────────
struct SensorData {
  float soilPercent;   // 0–100%, mapped from raw ADC
  float tempC;         // from DHT11; NaN on read failure
  float humidity;      // from DHT11; NaN on read failure
  bool  rainDetected;  // true = rain sensor DO pin is LOW
  float flowLitres;    // water volume since last read
};

SensorData lastReading = {0};  // holds the most recent sensor snapshot

// ─── Pump control ─────────────────────────────────────────────────────────────
// Always use these two functions to turn the pump on/off.
// They apply the RELAY_ACTIVE_LOW polarity defined in config.h,
// so the rest of the code never has to think about HIGH vs LOW.

void pumpOn() {
  if (digitalRead(PIN_PUMP_RELAY) == PUMP_ON) return;  // already on, skip
  digitalWrite(PIN_PUMP_RELAY, PUMP_ON);
  pumpOnTime = millis();  // record when pump started for safety timeout
  Serial.println("Pump ON");
}

void pumpOff() {
  if (digitalRead(PIN_PUMP_RELAY) == PUMP_OFF) return;  // already off, skip
  digitalWrite(PIN_PUMP_RELAY, PUMP_OFF);
  pumpOnTime = 0;  // reset timer
  Serial.println("Pump OFF");
}

// ─── NVS Threshold persistence ───────────────────────────────────────────────
// Supabase/backend can push new thresholds via MQTT. We save them to NVS
// (non-volatile storage) so they survive a power cut or reboot.

void loadThresholds() {
  prefs.begin("irr", true);  // "irr" = NVS namespace; true = read-only mode
  soilDryThreshold = prefs.getFloat("dry", DEFAULT_DRY_THRESHOLD);
  soilWetThreshold = prefs.getFloat("wet", DEFAULT_WET_THRESHOLD);
  prefs.end();
  Serial.printf("Thresholds loaded — dry: %.1f%%, wet: %.1f%%\n",
                soilDryThreshold, soilWetThreshold);
}

void saveThresholds(float dry, float wet) {
  prefs.begin("irr", false);  // false = read-write mode
  prefs.putFloat("dry", dry);
  prefs.putFloat("wet", wet);
  prefs.end();
  Serial.printf("Thresholds saved — dry: %.1f%%, wet: %.1f%%\n", dry, wet);
}

// ─── Step 9: Sensor read ──────────────────────────────────────────────────────
// Returns a SensorData snapshot. Called on its own timer (SENSOR_READ_INTERVAL)
// independently of the 30s publish interval.

SensorData readSensors() {
  SensorData d;

  // — Soil moisture —
  int raw = analogRead(PIN_SOIL);
  // Manual float mapping (avoids map()'s integer truncation):
  // SOIL_DRY_RAW → 0%, SOIL_WET_RAW → 100%
  d.soilPercent = (float)(SOIL_DRY_RAW - raw) /
                  (float)(SOIL_DRY_RAW - SOIL_WET_RAW) * 100.0f;
  d.soilPercent = constrain(d.soilPercent, 0.0f, 100.0f);  // clamp to 0–100

  // — DHT11 temperature & humidity —
  // Returns NaN on failure — the backend handles NaN gracefully
  d.tempC    = dht.readTemperature();
  d.humidity = dht.readHumidity();

  // — Rain sensor (digital DO pin) —
  // DO pin is LOW when rain is detected (module's onboard comparator pulls it LOW)
  d.rainDetected = (digitalRead(PIN_RAIN) == LOW);

  // — Flow sensor —
  // Snapshot pulse count atomically, then reset.
  // noInterrupts()/interrupts() prevent the ISR from modifying the counter
  // mid-copy, which would give a corrupted value.
  noInterrupts();
  uint32_t pulses = flowPulseCount;
  flowPulseCount  = 0;
  interrupts();
  // YF-S201 spec: ~450 pulses per litre (calibrate with a measuring jug)
  d.flowLitres = pulses / 450.0f;

  return d;
}

// ─── Step 10: Publish sensor JSON every 30s ───────────────────────────────────
// Builds a compact JSON string and sends it to devices/{id}/sensors.
// The Python backend will add a real UTC timestamp when it stores the record.

void publishSensors(const SensorData& d) {
  StaticJsonDocument<256> doc;
  doc["device_id"]   = DEVICE_ID;
  doc["soil_pct"]    = serialized(String(d.soilPercent, 1));  // 1 decimal place
  doc["temp_c"]      = isnan(d.tempC)    ? nullptr : serialized(String(d.tempC, 1));
  doc["humidity"]    = isnan(d.humidity) ? nullptr : serialized(String(d.humidity, 1));
  doc["rain"]        = d.rainDetected;
  doc["flow_litres"] = serialized(String(d.flowLitres, 3));

  char buffer[256];
  serializeJson(doc, buffer);

  if (mqtt.connected()) {
    bool ok = mqtt.publish(TOPIC_SENSORS, buffer);
    Serial.println(ok ? "Published sensors" : "Publish failed");
  }
}

// ─── Step 11: MQTT message handler ───────────────────────────────────────────
// PubSubClient calls this automatically on every incoming message.
// Handles three commands:
//   {"cmd": "pump_on"}
//   {"cmd": "pump_off"}
//   {"cmd": "set_threshold", "dry": 25.0, "wet": 65.0}

void handleThresholdUpdate(JsonDocument& doc) {
  // Use existing value as default if a key is missing from the JSON
  float dry = doc["dry"] | soilDryThreshold;
  float wet = doc["wet"] | soilWetThreshold;

  if (dry >= wet) {
    Serial.println("Invalid thresholds: dry must be < wet. Ignoring.");
    return;
  }
  soilDryThreshold = dry;
  soilWetThreshold = wet;
  saveThresholds(dry, wet);
}

void onMqttMessage(char* topic, byte* payload, unsigned int len) {
  char msg[len + 1];
  memcpy(msg, payload, len);
  msg[len] = '\0';

  Serial.printf("MQTT [%s]: %s\n", topic, msg);

  // 128 bytes fits all three command types including set_threshold fields
  StaticJsonDocument<128> doc;
  if (deserializeJson(doc, msg)) {
    Serial.println("Bad JSON, ignoring");
    return;
  }

  // Guard against missing "cmd" key — strcmp on a null pointer crashes the ESP32
  const char* cmd = doc["cmd"];
  if (!cmd) {
    Serial.println("No 'cmd' key, ignoring");
    return;
  }

  if      (strcmp(cmd, "pump_on")        == 0) pumpOn();
  else if (strcmp(cmd, "pump_off")       == 0) pumpOff();
  else if (strcmp(cmd, "set_threshold")  == 0) handleThresholdUpdate(doc);
  else Serial.printf("Unknown cmd: %s\n", cmd);
}

// ─── Step 12: Local fallback irrigation logic ────────────────────────────────
// Runs every loop iteration (not just every 30s) so the system reacts
// to rain or threshold crossings within SENSOR_READ_INTERVAL (2 seconds).
//
// This function is the safety net:
//   - Works with no WiFi
//   - Works with no MQTT
//   - Protects against pump running forever (safety timeout)

void localIrrigationLogic(const SensorData& d) {

  // ── Safety timeout: force pump off if it has run too long ──────────────────
  // Protects against backend crash, lost MQTT connection, or stuck pump_on command.
  if (pumpOnTime != 0 && (millis() - pumpOnTime) > MAX_PUMP_RUNTIME) {
    pumpOff();
    Serial.println("SAFETY: pump auto-shutoff after max runtime exceeded");
    return;
  }

  // ── Rain override: always stop pumping if rain detected ───────────────────
  if (d.rainDetected) {
    pumpOff();
    return;
  }

  // ── Threshold logic ───────────────────────────────────────────────────────
  if (d.soilPercent < soilDryThreshold) pumpOn();
  if (d.soilPercent > soilWetThreshold) pumpOff();
}

// ─── WiFi ────────────────────────────────────────────────────────────────────

void setupWiFi() {
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  Serial.print("Connecting to WiFi");
  // Blocking only at startup — acceptable here since nothing else is running yet
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi connected: " + WiFi.localIP().toString());
}

void maintainWiFi() {
  // Non-blocking: if WiFi dropped, start reconnect but don't wait for it.
  // Local irrigation logic keeps running in the meantime.
  if (WiFi.status() != WL_CONNECTED) {
    static uint32_t lastWiFiAttempt = 0;
    if (millis() - lastWiFiAttempt > 10000) {  // retry every 10s
      lastWiFiAttempt = millis();
      Serial.println("WiFi lost — reconnecting...");
      WiFi.disconnect();
      WiFi.begin(WIFI_SSID, WIFI_PASS);
    }
  }
}

// ─── MQTT ─────────────────────────────────────────────────────────────────────

void reconnectMqtt() {
  if (mqtt.connected()) return;
  if (WiFi.status() != WL_CONNECTED) return;  // no point trying without WiFi

  // static preserves this variable between calls without making it global
  static uint32_t lastAttempt = 0;
  if (millis() - lastAttempt < MQTT_RETRY_INTERVAL) return;  // non-blocking wait
  lastAttempt = millis();

  Serial.print("Connecting to MQTT...");
  if (mqtt.connect(DEVICE_ID, MQTT_USER, MQTT_PASS)) {
    Serial.println("connected");
    mqtt.subscribe(TOPIC_CONTROL);
  } else {
    Serial.printf("failed (rc=%d)\n", mqtt.state());
    // rc codes: -4=timeout, -3=denied, -2=unavailable, -1=bad protocol, 1=bad ID
  }
}

// ─── OTA (Over-The-Air updates) ───────────────────────────────────────────────
// Allows re-flashing firmware over WiFi — no USB cable needed after first deploy.
// Access via Arduino IDE → Tools → Port → Network Ports → esp32_01

void setupOTA() {
  ArduinoOTA.setHostname(DEVICE_ID);   // shows up by name on the network

  // Optional: set a password so random devices can't push firmware
  // ArduinoOTA.setPassword("your_ota_password");

  ArduinoOTA.onStart([]()  { Serial.println("OTA start");  });
  ArduinoOTA.onEnd([]()    { Serial.println("\nOTA done");  });
  ArduinoOTA.onError([](ota_error_t e) {
    Serial.printf("OTA error[%u]\n", e);
  });
  ArduinoOTA.onProgress([](unsigned int progress, unsigned int total) {
    Serial.printf("OTA %u%%\r", progress / (total / 100));
  });

  ArduinoOTA.begin();
  Serial.println("OTA ready");
}

// ─── setup() ─────────────────────────────────────────────────────────────────

void setup() {
  Serial.begin(115200);

  // Pump off immediately at boot — safety first
  pinMode(PIN_PUMP_RELAY, OUTPUT);
  pumpOff();

  // Flow sensor — interrupt fires on each rising edge (pulse front)
  pinMode(PIN_FLOW, INPUT_PULLUP);
  attachInterrupt(digitalPinToInterrupt(PIN_FLOW), onFlowPulse, RISING);

  // Rain sensor DO pin as input
  pinMode(PIN_RAIN, INPUT);

  dht.begin();
  loadThresholds();
  setupWiFi();

  mqtt.setServer(MQTT_BROKER, MQTT_PORT);
  mqtt.setCallback(onMqttMessage);

  setupOTA();

  // Watchdog timer: if loop() stops being called for WDT_TIMEOUT_SEC seconds,
  // the hardware automatically reboots the ESP32. Catches infinite loops,
  // sensor lockups, and memory issues.
  esp_task_wdt_init(WDT_TIMEOUT_SEC, true);  // true = panic/reboot on timeout
  esp_task_wdt_add(NULL);  // register the main loop task with the watchdog

  Serial.println("Setup complete");
}

// ─── loop() ──────────────────────────────────────────────────────────────────

void loop() {
  esp_task_wdt_reset();   // feed the watchdog — must happen within WDT_TIMEOUT_SEC

  maintainWiFi();         // reconnect WiFi if dropped (non-blocking)
  reconnectMqtt();        // reconnect MQTT if dropped (non-blocking)
  mqtt.loop();            // let PubSubClient process incoming messages
  ArduinoOTA.handle();    // check for pending OTA update

  // Read sensors on their own timer (DHT11 needs minimum 2s between reads)
  // Note: unsigned subtraction handles millis() ~49-day overflow safely
  if (millis() - lastSensorRead >= SENSOR_READ_INTERVAL) {
    lastSensorRead = millis();
    lastReading = readSensors();
    localIrrigationLogic(lastReading);  // runs every 2s — reacts to rain quickly
  }

  // Publish to MQTT every 30s using the most recent reading
  if (millis() - lastPublish >= PUBLISH_INTERVAL) {
    lastPublish = millis();
    publishSensors(lastReading);
  }
}
