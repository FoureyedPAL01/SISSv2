// esp32.ino
// SISS v2 - PWM Pump Control Version
// Uses D4184 MOSFET module for variable speed control

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

// PWM helper — uses ESP32 Core 3.x ledcWrite API
inline void setPumpPwm(int duty) { ledcWrite(PIN_PUMP_PWM, duty); }

// State
CropProfile cropProfile;
bool pumpRunning = false;
bool manualOverride = false;
unsigned long manualStartMs = 0;
long currentPumpLogId = -1;
int currentPwmDuty = DEFAULT_PWM_DUTY;  // Current PWM setting (0-255)
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
  
  // Extract PWM value if provided
  int pwmValue = DEFAULT_PWM_DUTY;
  if (doc["pwm"].is<int>()) {
    pwmValue = doc["pwm"].as<int>();
    currentPwmDuty = constrain(pwmValue, 0, 255);
  }

  // Handle PWM-only command (set speed without starting pump)
  if (cmd == "set_pwm" && doc["value"].is<int>()) {
    currentPwmDuty = constrain(doc["value"].as<int>(), 0, 255);
    setPumpPwm(currentPwmDuty);
    Serial.printf("[MQTT] PWM set to %d\n", currentPwmDuty);
    return;
  }

  // Pump ON command
  if (cmd == "pump_on" && !pumpRunning) {
    manualOverride = true;
    pumpRunning = true;
    manualStartMs = millis();
    
    // Use PWM control instead of relay
    setPumpPwm(currentPwmDuty);
    Serial.printf("[MQTT] Pump ON with PWM %d (~%d%%)\n", currentPwmDuty, (currentPwmDuty * 100) / 255);
    
    currentPumpLogId = postPumpLogStart(analogReadMoisture(), "manual");

    // Alert: manual pump started
    postAlert("pump_on", "Manual pump activated via app.");
  } 
  // Pump OFF command
  else if (cmd == "pump_off") {
    if (pumpRunning && currentPumpLogId > 0) {
      unsigned long durationSecs = (millis() - manualStartMs) / 1000;
      // Calculate actual water used based on PWM duty cycle
      float waterUsed = (durationSecs / 60.0f) * (currentPwmDuty / 255.0f) * 0.5f;
      patchPumpLogEnd(currentPumpLogId, analogReadMoisture(), durationSecs, waterUsed);
      currentPumpLogId = -1;
    }
    manualOverride = false;
    pumpRunning = false;
    setPumpPwm(0);  // PWM 0 = pump OFF
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

void connectMQTT() {
  if (mqtt.connected()) return;
  tlsClient.setInsecure();
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setCallback(mqttCallback);
  
  while (!mqtt.connected()) {
    String clientId = "siss-esp32-" + String((uint32_t)ESP.getEfuseMac());
    if (mqtt.connect(clientId.c_str(), MQTT_USER, MQTT_PASSWORD)) {
      mqtt.subscribe(MQTT_TOPIC_SUB);
      Serial.println("[MQTT] Connected & Subscribed!");
    } else {
      delay(5000);
    }
  }
}

void setup() {
  Serial.begin(115200);
  dht.begin();
  ledcAttach(PIN_PUMP_PWM, 1000, 8);  // ESP32 Core 3.x API
  pinMode(PIN_RAIN_SENSOR, INPUT);
  pinMode(PIN_SOIL_MOISTURE, INPUT);
  pinMode(PIN_FLOW_SENSOR, INPUT_PULLUP);
  attachInterrupt(digitalPinToInterrupt(PIN_FLOW_SENSOR), flowISR, FALLING);
  setPumpPwm(0);  // Ensure pump is off on boot

  // Run calibration mode if enabled
  if (CALIBRATION_MODE) {
    runCalibrationMode();
  }

  connectWiFi();
  connectMQTT();
  
  updateDeviceStatus("online");
  cropProfile = fetchCropProfile();
  
  // Use PWM from crop profile if available, otherwise default
  currentPwmDuty = (cropProfile.pwmDuty > 0) ? cropProfile.pwmDuty : DEFAULT_PWM_DUTY;
  Serial.printf("[Boot] Ready. Moisture low=%d%%, PWM duty=%d (~%d%%)\n", 
                cropProfile.moistureLow, currentPwmDuty, (currentPwmDuty * 100) / 255);
}

unsigned long lastRun = 0;
const unsigned long INTERVAL_MS = 5000UL; // 5 seconds

void loop() {
  connectWiFi();
  connectMQTT();
  mqtt.loop();

  // Manual Safety Timeout (2 mins)
  if (manualOverride && pumpRunning && (millis() - manualStartMs >= MANUAL_TIMEOUT_MS)) {
    if (currentPumpLogId > 0) {
      unsigned long durationSecs = (MANUAL_TIMEOUT_MS) / 1000;
      float waterUsed = (durationSecs / 60.0f) * (currentPwmDuty / 255.0f) * 0.5f;
      patchPumpLogEnd(currentPumpLogId, analogReadMoisture(), durationSecs, waterUsed);
      currentPumpLogId = -1;
    }
    manualOverride = false;
    pumpRunning = false;
    setPumpPwm(0);
    Serial.println("[System] Pump auto-stopped after 2 mins");

    // Alert: pump stopped by safety limit
    postAlert("pump_timeout",
              "Pump stopped automatically after the 2-minute safety limit.");
  }

  // 5-Second Sensor Loop
  if (millis() - lastRun >= INTERVAL_MS) {
    lastRun = millis();

    int moisture = analogReadMoisture();
    float temp = dht.readTemperature();
    float humidity = dht.readHumidity();
    bool rain = rainDetected();
    
    long pulses = flowPulseCount;
    flowPulseCount = 0;
    float flowLitres = (pulses / 7.5f / 60.0f) * (INTERVAL_MS / 1000.0f);

    Serial.printf("[Sensor] Moist:%d%% Temp:%.1fC Hum:%.1f%% Rain:%d PWM:%d Flow:%.3fL\n", 
                   moisture, temp, humidity, (int)rain, currentPwmDuty, flowLitres);

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
          Serial.printf("[Auto] Soil dry & no rain expected. Starting pump at PWM %d...\n", currentPwmDuty);
          
          // Get PWM duty from crop profile, fallback to default
          int autoPwmDuty = (cropProfile.pwmDuty > 0) ? cropProfile.pwmDuty : DEFAULT_PWM_DUTY;
          currentPumpLogId = postPumpLogStart(moisture, "auto");

          // Alert: auto irrigation started
          char onMsg[80];
          snprintf(onMsg, sizeof(onMsg),
                   "Auto irrigation started — soil moisture at %d%%.", moisture);
          postAlert("auto_irrigation_started", String(onMsg));
          Serial.println("[Alert] auto_irrigation_started sent");

          pumpRunning = true;
          setPumpPwm(autoPwmDuty);  // PWM control
          delay((unsigned long)cropProfile.irrigateSecs * 1000UL); // Block for duration
          setPumpPwm(0);  // PWM 0 = OFF
          pumpRunning = false;
          
          int afterMoisture = analogReadMoisture();
          float waterUsed = (cropProfile.irrigateSecs / 60.0f) * (autoPwmDuty / 255.0f) * 0.5f;
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