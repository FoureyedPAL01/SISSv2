#include <WiFi.h>
#include <PubSubClient.h>
#include <DHT.h>
#include <ArduinoJson.h>
#include <Preferences.h>
#include <ArduinoOTA.h>
#include "config.h"
#include "SensorData.h"  // Struct in a separate header to avoid Arduino IDE
                         // auto-prototype injection ordering bug

// ─── Objects ─────────────────────────────────────────────
WiFiClient   espClient;
PubSubClient mqtt(espClient);
DHT          dht(PIN_DHT, DHT11);
Preferences  prefs;

// ─── State ───────────────────────────────────────────────
float    soilDryThreshold = DEFAULT_DRY_THRESHOLD;
float    soilWetThreshold = DEFAULT_WET_THRESHOLD;
uint32_t pumpOnTime       = 0;
uint32_t lastSensorRead   = 0;
uint32_t lastPublish      = 0;

// ─── Flow sensor ISR ─────────────────────────────────────
// volatile: modified inside interrupt — compiler must not cache it
// IRAM_ATTR: ISR must run from fast RAM, not flash
volatile uint32_t flowPulseCount = 0;
void IRAM_ATTR onFlowPulse() { flowPulseCount++; }

// ─── Sensor data ─────────────────────────────────────────
// SensorData struct lives in SensorData.h
SensorData lastReading = {0};

// ─── Pump control ────────────────────────────────────────
void pumpOn() {
  if (digitalRead(PIN_PUMP_RELAY) == PUMP_ON) return;
  digitalWrite(PIN_PUMP_RELAY, PUMP_ON);
  pumpOnTime = millis();
  // Guard against millis() returning exactly 0 at the moment the pump turns
  // on — that value is the sentinel meaning "pump is OFF", so the safety
  // timeout check (pumpOnTime != 0) would never fire.
  if (pumpOnTime == 0) pumpOnTime = 1;
  Serial.println("Pump ON");
}

void pumpOff() {
  if (digitalRead(PIN_PUMP_RELAY) == PUMP_OFF) return;
  digitalWrite(PIN_PUMP_RELAY, PUMP_OFF);
  pumpOnTime = 0;
  Serial.println("Pump OFF");
}

// ─── NVS threshold persistence ───────────────────────────
void loadThresholds() {
  prefs.begin("irr", true);
  soilDryThreshold = prefs.getFloat("dry", DEFAULT_DRY_THRESHOLD);
  soilWetThreshold = prefs.getFloat("wet", DEFAULT_WET_THRESHOLD);
  prefs.end();
  Serial.printf("Thresholds: dry=%.1f%% wet=%.1f%%\n",
                soilDryThreshold, soilWetThreshold);
}

void saveThresholds(float dry, float wet) {
  prefs.begin("irr", false);
  prefs.putFloat("dry", dry);
  prefs.putFloat("wet", wet);
  prefs.end();
}

// ─── Sensor read ─────────────────────────────────────────
SensorData readSensors() {
  SensorData d;

  int raw = analogRead(PIN_SOIL);
  d.soilPercent = (float)(SOIL_DRY_RAW - raw) /
                  (float)(SOIL_DRY_RAW - SOIL_WET_RAW) * 100.0f;
  d.soilPercent = constrain(d.soilPercent, 0.0f, 100.0f);

  d.tempC        = dht.readTemperature();
  d.humidity     = dht.readHumidity();
  d.rainDetected = (digitalRead(PIN_RAIN) == LOW);

  // Atomically snapshot and reset pulse counter
  noInterrupts();
  uint32_t pulses = flowPulseCount;
  flowPulseCount  = 0;
  interrupts();
  d.flowLitres = pulses / 450.0f;  // YF-S201: ~450 pulses/litre

  return d;
}

// ─── MQTT publish ─────────────────────────────────────────
void publishSensors(const SensorData& d) {
  if (!mqtt.connected()) return;

  JsonDocument doc;
  doc["device_id"]   = DEVICE_ID;
  doc["soil_pct"]    = round(d.soilPercent * 10) / 10.0;
  doc["rain"]        = d.rainDetected;
  doc["flow_litres"] = round(d.flowLitres * 1000) / 1000.0;

  if (!isnan(d.tempC))    doc["temp_c"]   = round(d.tempC * 10) / 10.0;
  if (!isnan(d.humidity)) doc["humidity"] = round(d.humidity * 10) / 10.0;

  // Use measureJson() to size the buffer exactly rather than a fixed 256-byte
  // array that would silently truncate if the payload exceeded it.
  size_t needed = measureJson(doc) + 1;
  char buffer[needed];
  size_t written = serializeJson(doc, buffer, needed);
  if (written == 0) {
    Serial.println("JSON serialisation failed");
    return;
  }

  bool ok = mqtt.publish(TOPIC_SENSORS, buffer);
  Serial.println(ok ? "Published" : "Publish failed");
}

// ─── MQTT command handler ────────────────────────────────
void onMqttMessage(char* topic, byte* payload, unsigned int len) {
  // Use a fixed-size buffer instead of a VLA (char msg[len+1]).
  // A VLA sized from an untrusted network packet can overflow the stack
  // and crash the device if a large or malformed packet arrives.
  const unsigned int MAX_MSG_LEN = 256;
  if (len >= MAX_MSG_LEN) {
    Serial.printf("MQTT message too long (%u bytes), ignored\n", len);
    return;
  }
  char msg[MAX_MSG_LEN];
  memcpy(msg, payload, len);
  msg[len] = '\0';
  Serial.printf("MQTT [%s]: %s\n", topic, msg);

  JsonDocument doc;
  if (deserializeJson(doc, msg)) { Serial.println("Bad JSON"); return; }

  const char* cmd = doc["cmd"];
  if (!cmd) return;

  if      (strcmp(cmd, "pump_on")  == 0) pumpOn();
  else if (strcmp(cmd, "pump_off") == 0) pumpOff();
  else if (strcmp(cmd, "set_threshold") == 0) {
    float dry = doc["dry"] | soilDryThreshold;
    float wet = doc["wet"] | soilWetThreshold;
    // Also validate the physical 0–100 % range, not just dry < wet.
    // Without this, out-of-range values corrupt NVS and permanently
    // break irrigation logic.
    if (dry < wet && dry >= 0.0f && wet <= 100.0f) {
      soilDryThreshold = dry;
      soilWetThreshold = wet;
      saveThresholds(dry, wet);
      Serial.printf("Thresholds updated: dry=%.1f wet=%.1f\n", dry, wet);
    } else {
      Serial.println("Invalid thresholds — ignored");
    }
  }
}

// ─── Local fallback irrigation logic ─────────────────────
// Runs every 2 s — keeps irrigating even with no WiFi/MQTT
void localIrrigationLogic(const SensorData& d) {

  // Safety: force pump off after 30 minutes
  if (pumpOnTime != 0 && (millis() - pumpOnTime) > MAX_PUMP_RUNTIME) {
    pumpOff();
    Serial.println("SAFETY: pump max runtime exceeded");
    return;
  }

  // Skip irrigation decisions when the DHT read has failed (returns NaN).
  // The original code ignored sensor validity, so a failed read could leave
  // soil-moisture as the only guard with no indication anything was wrong.
  if (isnan(d.tempC) || isnan(d.humidity)) {
    Serial.println("Sensor read failed — skipping irrigation decision");
    return;
  }

  if (d.rainDetected)                     { pumpOff(); return; }
  if (d.soilPercent < soilDryThreshold)     pumpOn();
  if (d.soilPercent > soilWetThreshold)     pumpOff();
}

// ─── WiFi ────────────────────────────────────────────────
void setupWiFi() {
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  Serial.print("WiFi connecting");
  // Timeout after 15 s so the device doesn't block indefinitely at boot
  // when the AP is unreachable. Local irrigation still works without WiFi.
  uint32_t start = millis();
  while (WiFi.status() != WL_CONNECTED) {
    if (millis() - start > 15000) {
      Serial.println("\nWiFi timeout — continuing without network");
      return;
    }
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi connected: " + WiFi.localIP().toString());
}

void maintainWiFi() {
  if (WiFi.status() == WL_CONNECTED) return;
  static uint32_t last = 0;
  if (millis() - last > 10000) {
    last = millis();
    WiFi.disconnect();
    WiFi.begin(WIFI_SSID, WIFI_PASS);
    Serial.println("WiFi reconnecting...");
  }
}

// ─── MQTT ────────────────────────────────────────────────
void reconnectMqtt() {
  if (mqtt.connected() || WiFi.status() != WL_CONNECTED) return;
  static uint32_t last = 0;
  if (millis() - last < MQTT_RETRY_INTERVAL) return;
  last = millis();

  Serial.print("MQTT connecting...");
  if (mqtt.connect(DEVICE_ID, MQTT_USER, MQTT_PASS)) {
    Serial.println("connected");
    mqtt.subscribe(TOPIC_CONTROL);
  } else {
    Serial.printf("failed rc=%d\n", mqtt.state());
  }
}

// ─── OTA ─────────────────────────────────────────────────
void setupOTA() {
  ArduinoOTA.setHostname(DEVICE_ID);
  ArduinoOTA.onStart([]()  { Serial.println("OTA start"); });
  ArduinoOTA.onEnd([]()    { Serial.println("OTA done");  });
  ArduinoOTA.onError([](ota_error_t e) { Serial.printf("OTA error %u\n", e); });
  ArduinoOTA.begin();
  Serial.println("OTA ready");
}

// ─── Setup ───────────────────────────────────────────────
void setup() {
  Serial.begin(115200);

  pinMode(PIN_PUMP_RELAY, OUTPUT);
  pumpOff();

  pinMode(PIN_FLOW, INPUT_PULLUP);
  attachInterrupt(digitalPinToInterrupt(PIN_FLOW), onFlowPulse, RISING);

  // INPUT_PULLUP prevents a floating pin from triggering false rain events
  // when no external pull-up resistor is fitted on the rain sensor DO line.
  pinMode(PIN_RAIN, INPUT_PULLUP);

  dht.begin();
  loadThresholds();
  setupWiFi();

  mqtt.setServer(MQTT_BROKER, MQTT_PORT);
  mqtt.setCallback(onMqttMessage);

  setupOTA();
  Serial.println("Setup complete");
}

// ─── Loop ────────────────────────────────────────────────
void loop() {
  maintainWiFi();
  reconnectMqtt();
  mqtt.loop();
  ArduinoOTA.handle();

  // Read sensors every 2 s (DHT11 minimum interval)
  if (millis() - lastSensorRead >= SENSOR_READ_INTERVAL) {
    lastSensorRead = millis();
    lastReading = readSensors();
    localIrrigationLogic(lastReading);
  }

  // Publish to MQTT every 30 s
  if (millis() - lastPublish >= PUBLISH_INTERVAL) {
    lastPublish = millis();
    publishSensors(lastReading);
  }
}