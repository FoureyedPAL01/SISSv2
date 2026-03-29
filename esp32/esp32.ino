// esp32.ino
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

// State
CropProfile cropProfile;
bool pumpRunning = false;
bool manualOverride = false;
unsigned long manualStartMs = 0;
long currentPumpLogId = -1;
const unsigned long MANUAL_TIMEOUT_MS = 120000UL; // 2 minutes auto-off

// MQTT & WiFi
WiFiClientSecure tlsClient;
PubSubClient mqtt(tlsClient);

void mqttCallback(char* topic, byte* payload, unsigned int length) {
  String msg;
  for (unsigned int i = 0; i < length; i++) msg += (char)payload[i];

  JsonDocument doc;
  deserializeJson(doc, msg);
  String cmd = doc["command"].as<String>();

  if (cmd == "pump_on" && !pumpRunning) {
    manualOverride = true;
    pumpRunning = true;
    manualStartMs = millis();
    digitalWrite(PIN_PUMP_RELAY, HIGH);
    currentPumpLogId = postPumpLogStart(analogReadMoisture(), "manual");
    Serial.println("[MQTT] Manual pump ON - 2 min safety timer started");
  } else if (cmd == "pump_off") {
    if (pumpRunning && currentPumpLogId > 0) {
      unsigned long durationSecs = (millis() - manualStartMs) / 1000;
      float waterUsed = (durationSecs / 60.0f) * 0.5f; // Estimate
      patchPumpLogEnd(currentPumpLogId, analogReadMoisture(), durationSecs, waterUsed);
      currentPumpLogId = -1;
    }
    manualOverride = false;
    pumpRunning = false;
    digitalWrite(PIN_PUMP_RELAY, LOW);
    Serial.println("[MQTT] Manual pump OFF");
  }
}

int analogReadMoisture() {
  int raw = analogRead(PIN_SOIL_MOISTURE);
  return constrain(map(raw, 4095, 1000, 0, 100), 0, 100);
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
  pinMode(PIN_PUMP_RELAY, OUTPUT);
  pinMode(PIN_RAIN_SENSOR, INPUT);
  attachInterrupt(digitalPinToInterrupt(PIN_FLOW_SENSOR), flowISR, RISING);
  digitalWrite(PIN_PUMP_RELAY, LOW);

  connectWiFi();
  connectMQTT();
  
  updateDeviceStatus("online");
  cropProfile = fetchCropProfile();
}

unsigned long lastRun = 0;
const unsigned long INTERVAL_MS = 5000UL; // 5 seconds - real-time

void loop() {
  connectWiFi();
  connectMQTT();
  mqtt.loop(); // Instantly processes manual commands from Flutter

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
    digitalWrite(PIN_PUMP_RELAY, LOW);
    Serial.println("[System] Manual pump auto-stopped after 2 mins");
  }

  // 30-Second Sensor Loop
  if (millis() - lastRun >= INTERVAL_MS) {
    lastRun = millis();

    int moisture = analogReadMoisture();
    float temp = dht.readTemperature();
    float humidity = dht.readHumidity();
    bool rain = (digitalRead(PIN_RAIN_SENSOR) == HIGH);
    
    long pulses = flowPulseCount;
    flowPulseCount = 0;
    float flowLitres = (pulses / 7.5f / 60.0f) * (INTERVAL_MS / 1000.0f);

    Serial.printf("[Sensor] Moist:%d%% Temp:%.1fC Hum:%.1f%% Rain:%d Flow:%.3fL\n", 
                   moisture, temp, humidity, (int)rain, flowLitres);

    postSensorReading(moisture, temp, humidity, rain, flowLitres);
    updateDeviceStatus("online");

    // Auto-Irrigation Logic
    if (!manualOverride) {
      if (!rain && moisture < cropProfile.moistureLow) {
        int rainPct = getRainForecastPct();
        if (rainPct < cropProfile.rainSkipPct) {
           Serial.println("[Auto] Soil dry & no rain expected. Starting pump!");
           currentPumpLogId = postPumpLogStart(moisture, "auto");
           
           pumpRunning = true;
           digitalWrite(PIN_PUMP_RELAY, HIGH);
           delay((unsigned long)cropProfile.irrigateSecs * 1000UL); // Block for duration
           digitalWrite(PIN_PUMP_RELAY, LOW);
           pumpRunning = false;
           
           int afterMoisture = analogReadMoisture();
           float waterUsed = (cropProfile.irrigateSecs / 60.0f) * 0.5f; // Estimation
           patchPumpLogEnd(currentPumpLogId, afterMoisture, cropProfile.irrigateSecs, waterUsed);
           currentPumpLogId = -1;
        }
      }
    }
  }
}
