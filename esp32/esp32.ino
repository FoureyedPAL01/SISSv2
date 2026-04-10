// esp32.ino
// RootSync - Relay-based Pump Control
// Uses relay module for ON/OFF pump control

#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>
#include <DHT.h>
#include "config.h"
#include "supabase_client.h"
#include "weather_client.h"

// Hardware
DHT dht(PIN_DHT, DHT11);
volatile long flowPulseCount = 0;
void IRAM_ATTR flowISR() { flowPulseCount++; }

// Relay helper — uses digitalWrite for ON/OFF control
inline void setPumpRelay(bool state) { digitalWrite(PIN_PUMP_RELAY, state ? HIGH : LOW); }

// State
CropProfile cropProfile;
bool pumpRunning = false;
bool manualOverride = false;
unsigned long manualStartMs = 0;
long currentPumpLogId = -1;
const unsigned long MANUAL_TIMEOUT_MS = 120000UL; // 2 minutes auto-off

// Alert state
unsigned long lastSoilAlertMs = 0;    // cooldown for soil_dry
bool prevRain = false;                // edge detection for rain_started/stopped

// MQTT & WiFi
WiFiClientSecure tlsClient;
PubSubClient mqtt(tlsClient);

void mqttCallback(char* topic, byte* payload, unsigned int length) {
  String msg;
  for (unsigned int i = 0; i < length; i++) msg += (char)payload[i];

  JsonDocument doc;
  deserializeJson(doc, msg);
  String cmd = doc["command"].as<String>();

  // Pump ON command
  if (cmd == "on" && !pumpRunning) {
    manualOverride = true;
    pumpRunning = true;
    manualStartMs = millis();
    
    setPumpRelay(true);
    Serial.println("[MQTT] Pump ON");
    
    currentPumpLogId = postPumpLogStart(analogReadMoisture(), "manual");

    // Alert: manual pump started
    postAlert("pump_on", "Manual pump activated via app.");
  } 
  // Pump OFF command
  else if (cmd == "off") {
    if (pumpRunning && currentPumpLogId > 0) {
      unsigned long durationSecs = (millis() - manualStartMs) / 1000;
      // Water usage: assume 0.5 L/min at full speed
      float waterUsed = (durationSecs / 60.0f) * 0.5f;
      patchPumpLogEnd(currentPumpLogId, analogReadMoisture(), durationSecs, waterUsed);
      currentPumpLogId = -1;
    }
    manualOverride = false;
    pumpRunning = false;
    setPumpRelay(false);
    Serial.println("[MQTT] Pump OFF");

    // Alert: manual pump stopped
    postAlert("pump_off", "Manual pump stopped via app.");
  }
}

// Read moisture sensor and convert to percentage using calibration values
// Higher raw ADC = drier soil, lower raw ADC = wetter soil
int analogReadMoisture() {
  int raw = analogRead(PIN_SOIL_MOISTURE);
  return constrain(map(raw, MOISTURE_AIR_RAW, MOISTURE_WATER_RAW, 0, 100), 0, 100);
}

// Read raw moisture ADC value (for calibration mode)
int readMoistureRaw() {
  return analogRead(PIN_SOIL_MOISTURE);
}

// Read raw rain sensor value (for calibration mode)
int readRainRaw() {
  return digitalRead(PIN_RAIN_SENSOR);
}

// Detect rain based on sensor type configuration
// RAIN_SENSOR_INVERT false: LOW = wet (most common YL-38 modules)
// RAIN_SENSOR_INVERT true: HIGH = wet
bool rainDetected() {
  int raw = digitalRead(PIN_RAIN_SENSOR);
  return RAIN_SENSOR_INVERT ? (raw == HIGH) : (raw == LOW);
}

// Calibration mode - prints raw sensor values every second
// Run with CALIBRATION_MODE true, set to false after calibration
void runCalibrationMode() {
  Serial.println("\n[CAL] ===============================================");
  Serial.println("[CAL]      SENSOR CALIBRATION MODE");
  Serial.println("[CAL] ===============================================");
  Serial.println("[CAL]");
  Serial.println("[CAL] SOIL MOISTURE:");
  Serial.printf("[CAL]   Current raw value: %d\n", readMoistureRaw());
  Serial.println("[CAL]   1. Hold sensor in DRY AIR - note value");
  Serial.println("[CAL]   2. Dip sensor in WATER - note value");
  Serial.println("[CAL]   3. Update MOISTURE_AIR_RAW and MOISTURE_WATER_RAW in config.h");
  Serial.println("[CAL]");
  Serial.println("[CAL] RAIN SENSOR:");
  Serial.printf("[CAL]   Current raw value: %d\n", readRainRaw());
  Serial.println("[CAL]   1. Keep sensor DRY - note value");
  Serial.println("[CAL]   2. Drop WATER on sensor - note value");
  Serial.println("[CAL]   3. If DRY=1 & WET=0: RAIN_SENSOR_INVERT = false");
  Serial.println("[CAL]   4. If DRY=0 & WET=1: RAIN_SENSOR_INVERT = true");
  Serial.println("[CAL]");
  Serial.println("[CAL] ===============================================\n");
  
  unsigned long calibrationStart = millis();
  const unsigned long CALIBRATION_DURATION = 30000UL; // 30 seconds
  
  while (millis() - calibrationStart < CALIBRATION_DURATION) {
    int moistureRaw = readMoistureRaw();
    int rainRaw = readRainRaw();
    int moisturePct = constrain(map(moistureRaw, MOISTURE_AIR_RAW, MOISTURE_WATER_RAW, 0, 100), 0, 100);
    
    Serial.printf("[CAL] Moisture: raw=%4d (≈%3d%%) | Rain: raw=%d | Time: %lus\n",
                  moistureRaw, moisturePct, rainRaw, (millis() - calibrationStart) / 1000);
    
    delay(1000);
  }
  
  Serial.println("[CAL] ===============================================");
  Serial.println("[CAL] Calibration mode complete!");
  Serial.println("[CAL] Set CALIBRATION_MODE = false in config.h");
  Serial.println("[CAL] ===============================================\n");
}

void connectWiFi() {
  if (WiFi.status() == WL_CONNECTED) return;
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("[WiFi] Connecting");
  while (WiFi.status() != WL_CONNECTED) { delay(500); Serial.print("."); }
  Serial.println("\n[WiFi] Connected!");
}

unsigned long lastMqttConnectAttempt = 0;

void connectMQTT() {
  if (mqtt.connected()) return;
  if (millis() - lastMqttConnectAttempt < 5000 && lastMqttConnectAttempt != 0) return;
  lastMqttConnectAttempt = millis();

  tlsClient.setInsecure();
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setCallback(mqttCallback);
  
  String clientId = "siss-esp32-" + String((uint32_t)ESP.getEfuseMac());
  if (mqtt.connect(clientId.c_str(), MQTT_USER, MQTT_PASSWORD)) {
    mqtt.subscribe(MQTT_TOPIC_SUB);
    Serial.println("[MQTT] Connected & Subscribed!");
  } else {
    Serial.print("[MQTT] Connect failed. rc=");
    Serial.println(mqtt.state());
  }
}

void setup() {
  Serial.begin(115200);
  dht.begin();
  pinMode(PIN_PUMP_RELAY, OUTPUT);
  pinMode(PIN_RAIN_SENSOR, INPUT);
  pinMode(PIN_SOIL_MOISTURE, INPUT);
  pinMode(PIN_FLOW_SENSOR, INPUT_PULLUP);
  attachInterrupt(digitalPinToInterrupt(PIN_FLOW_SENSOR), flowISR, FALLING);
  setPumpRelay(false);  // Ensure pump is off on boot

  // Run calibration mode if enabled
  if (CALIBRATION_MODE) {
    runCalibrationMode();
  }

  connectWiFi();
  connectMQTT();
  
  updateDeviceStatus("online");
  cropProfile = fetchCropProfile();
  
  Serial.printf("[Boot] Ready. Moisture low=%d%%\n", cropProfile.moistureLow);
}

unsigned long lastRun = 0;
const unsigned long INTERVAL_MS = 5000UL; // 5 seconds

void loop() {
  connectWiFi();
  connectMQTT();
  if (mqtt.connected()) {
    mqtt.loop();
  }

  // Manual Safety Timeout (2 mins)
  if (manualOverride && pumpRunning && (millis() - manualStartMs >= MANUAL_TIMEOUT_MS)) {
    if (currentPumpLogId > 0) {
      unsigned long durationSecs = (MANUAL_TIMEOUT_MS) / 1000;
      float waterUsed = (durationSecs / 60.0f) * 0.5f;
      patchPumpLogEnd(currentPumpLogId, analogReadMoisture(), durationSecs, waterUsed);
      currentPumpLogId = -1;
    }
    manualOverride = false;
    pumpRunning = false;
    setPumpRelay(false);
    Serial.println("[System] Pump auto-stopped after 2 mins");

    // Alert: pump stopped by safety limit
    postAlert("pump_timeout",
              "Pump stopped automatically after the 2-minute safety limit.");
  }

  // 5-Second Sensor Loop
  if (millis() - lastRun >= INTERVAL_MS) {
    lastRun = millis();

    // Check for commands from Supabase ALWAYS (fallback logic from app)
    String cmd = fetchDeviceCommand();
    if (cmd == "on" && !pumpRunning) {
      manualOverride = true;
      pumpRunning = true;
      manualStartMs = millis();
      setPumpRelay(true);
      Serial.println("[Supabase] Pump ON");
      currentPumpLogId = postPumpLogStart(analogReadMoisture(), "manual");
      postAlert("pump_on", "Manual pump activated via app.");
    } else if (cmd == "off" && pumpRunning) {
      if (currentPumpLogId > 0) {
        unsigned long durationSecs = (millis() - manualStartMs) / 1000;
        float waterUsed = (durationSecs / 60.0f) * 0.5f;
        patchPumpLogEnd(currentPumpLogId, analogReadMoisture(), durationSecs, waterUsed);
        currentPumpLogId = -1;
      }
      manualOverride = false;
      pumpRunning = false;
      setPumpRelay(false);
      Serial.println("[Supabase] Pump OFF");
      postAlert("pump_off", "Manual pump stopped via app.");
    }

    int moisture = analogReadMoisture();
    float temp = dht.readTemperature();
    float humidity = dht.readHumidity();
    bool rain = rainDetected();
    
    long pulses = flowPulseCount;
    flowPulseCount = 0;
    float flowLitres = (pulses / 7.5f / 60.0f) * (INTERVAL_MS / 1000.0f);

    Serial.printf("[Sensor] Moist:%d%% Temp:%.1fC Hum:%.1f%% Rain:%d Flow:%.3fL\n", 
                   moisture, temp, humidity, (int)rain, flowLitres);

    postSensorReading(moisture, temp, humidity, rain, flowLitres);
    updateDeviceStatus("online");

    // ── Alert: rain started (rising edge) ─────────────────────────────────────
    if (rain && !prevRain) {
      postAlert("rain_started", "Rain detected — automatic irrigation paused.");
      Serial.println("[Alert] rain_started sent");
    }

    // ── Alert: rain stopped (falling edge) ────────────────────────────────────
    if (!rain && prevRain) {
      postAlert("rain_stopped", "Rain stopped — automatic irrigation resumed.");
      Serial.println("[Alert] rain_stopped sent");
    }

    prevRain = rain;

    // ── Alert: soil dry ──────────────────────────────────────────────────────
    // Only fires if the pump isn't already running (no point alerting mid-irrigation)
    if (!pumpRunning && !rain
        && moisture < cropProfile.moistureLow
        && (millis() - lastSoilAlertMs >= ALERT_COOLDOWN_SOIL_MS)) {
      lastSoilAlertMs = millis();
      char msg[80];
      snprintf(msg, sizeof(msg),
               "Soil moisture at %d%% — below threshold of %d%%.",
               moisture, cropProfile.moistureLow);
      postAlert("soil_dry", String(msg));
      Serial.printf("[Alert] soil_dry sent (%d%%)\n", moisture);
    }

    // Auto-Irrigation Logic
    if (!manualOverride) {
      if (!rain && moisture < cropProfile.moistureLow) {
        int rainPct = getRainForecastPct();
        if (rainPct < cropProfile.rainSkipPct) {
          Serial.println("[Auto] Soil dry & no rain expected. Starting pump...");
          
          currentPumpLogId = postPumpLogStart(moisture, "auto");

          // Alert: auto irrigation started
          char onMsg[80];
          snprintf(onMsg, sizeof(onMsg),
                   "Auto irrigation started — soil moisture at %d%.", moisture);
          postAlert("auto_irrigation_started", String(onMsg));
          Serial.println("[Alert] auto_irrigation_started sent");

          pumpRunning = true;
          setPumpRelay(true);  // Pump ON
          delay((unsigned long)cropProfile.irrigateSecs * 1000UL); // Block for duration
          setPumpRelay(false);  // Pump OFF
          pumpRunning = false;
          
          int afterMoisture = analogReadMoisture();
          float waterUsed = (cropProfile.irrigateSecs / 60.0f) * 0.5f;
          patchPumpLogEnd(currentPumpLogId, afterMoisture, cropProfile.irrigateSecs, waterUsed);
          currentPumpLogId = -1;

          // Alert: auto irrigation finished
          char offMsg[100];
          snprintf(offMsg, sizeof(offMsg),
                   "Auto irrigation complete — soil moisture now %d%% after %d seconds.",
                   afterMoisture, cropProfile.irrigateSecs);
          postAlert("auto_irrigation_stopped", String(offMsg));
          Serial.printf("[Alert] auto_irrigation_stopped sent. Water used: %.2fL\n", waterUsed);
        }
      }
    }
  }
}