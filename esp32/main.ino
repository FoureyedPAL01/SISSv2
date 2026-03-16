// main.ino
// SISS v2 -- Full ESP32 firmware.
// No Python backend. No local MQTT broker.
// ESP32 talks directly to Supabase REST API and HiveMQ Cloud.

#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>
#include <DHT.h>
#include "config.h"
#include "supabase_client.h"
#include "weather_client.h"

// -- Hardware setup --------------------------------------------------------
DHT dht(PIN_DHT, DHT11);

// volatile: this variable is modified inside an interrupt handler.
// The compiler must not cache it in a register -- reads must always go to RAM.
// IRAM_ATTR: store the interrupt handler in fast internal RAM, not flash.
volatile long flowPulseCount = 0;
void IRAM_ATTR flowISR() { flowPulseCount++; }

// -- State -----------------------------------------------------------------
CropProfile cropProfile;
bool pumpRunning    = false;
bool manualOverride = false;

// Fault detection: circular buffer of last STUCK_N moisture readings
const int STUCK_N = 10;
int  moistureHist[STUCK_N];
int  moistureHistIdx = 0;
bool histFull        = false;

// -- MQTT ------------------------------------------------------------------
WiFiClientSecure tlsClient;
PubSubClient     mqtt(tlsClient);

// MQTT callback -- fires immediately when a subscribed message arrives.
// topic: which MQTT topic the message came from (char array)
// payload: raw bytes of the message body
// length: number of bytes in payload
void mqttCallback(char* topic, byte* payload, unsigned int length) {
  String msg;
  for (unsigned int i = 0; i < length; i++) msg += (char)payload[i];

  JsonDocument doc;
  deserializeJson(doc, msg);
  String cmd = doc["command"].as<String>();

  if (cmd == "pump_on" && !pumpRunning) {
    manualOverride = true;
    pumpRunning    = true;
    digitalWrite(PIN_PUMP_RELAY, HIGH);
    postPumpLogStart(analogReadMoisture(), "manual");
    Serial.println("[MQTT] Manual pump ON");
  } else if (cmd == "pump_off") {
    manualOverride = false;
    pumpRunning    = false;
    digitalWrite(PIN_PUMP_RELAY, LOW);
    Serial.println("[MQTT] Manual pump OFF");
  }
}

// -- Helpers ---------------------------------------------------------------

// Read raw ADC and map to 0-100% moisture.
// Capacitive sensors: dry = high ADC value, wet = low ADC value.
// Calibrate 4095/1000 bounds to your specific sensor by testing with dry and wet soil.
int analogReadMoisture() {
  int raw = analogRead(PIN_SOIL_MOISTURE);
  return constrain(map(raw, 4095, 1000, 0, 100), 0, 100);
}

void connectWiFi() {
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("[WiFi] Connecting");
  while (WiFi.status() != WL_CONNECTED) { delay(500); Serial.print("."); }
  Serial.println(" connected: " + WiFi.localIP().toString());
}

void connectMQTT() {
  tlsClient.setInsecure();
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setCallback(mqttCallback);
  mqtt.setBufferSize(512);

  while (!mqtt.connected()) {
    // Client ID must be unique per HiveMQ connection.
    // Using chip MAC ensures uniqueness if multiple ESP32s share credentials.
    String clientId = "siss-esp32-" + String((uint32_t)ESP.getEfuseMac());
    Serial.print("[MQTT] Connecting...");
    if (mqtt.connect(clientId.c_str(), MQTT_USER, MQTT_PASSWORD)) {
      mqtt.subscribe(MQTT_TOPIC_SUB);
      Serial.println("connected");
    } else {
      Serial.println("failed (rc=" + String(mqtt.state()) + "), retry in 5s");
      delay(5000);
    }
  }
}

void checkFaultDetection(int moisture) {
  moistureHist[moistureHistIdx % STUCK_N] = moisture;
  moistureHistIdx++;
  if (moistureHistIdx >= STUCK_N) histFull = true;

  if (histFull) {
    bool stuck = true;
    for (int i = 1; i < STUCK_N; i++) {
      if (moistureHist[i] != moistureHist[0]) { stuck = false; break; }
    }
    if (stuck)
      insertAlert("sensor_stuck",
                  "Soil moisture unchanged for " + String(STUCK_N) + " readings");
  }
}

// -- setup() -- runs once on power-on -------------------------------------
void setup() {
  Serial.begin(115200);
  dht.begin();
  pinMode(PIN_PUMP_RELAY,  OUTPUT);
  pinMode(PIN_RAIN_SENSOR, INPUT);
  attachInterrupt(digitalPinToInterrupt(PIN_FLOW_SENSOR), flowISR, RISING);
  digitalWrite(PIN_PUMP_RELAY, LOW);  // ensure pump is OFF on boot

  connectWiFi();
  connectMQTT();
  updateDeviceStatus("online");

  // Load crop profile thresholds from Supabase into RAM.
  // Pass "" to use defaults; for full implementation, first GET the devices row
  // to read crop_profile_id, then pass that value here.
  cropProfile = fetchCropProfile("");
  Serial.println("[Boot] Ready. Moisture low=" + String(cropProfile.moistureLow) +
                 " high=" + String(cropProfile.moistureHigh));
}

// -- loop() -- runs repeatedly --------------------------------------------
unsigned long lastRun = 0;
const unsigned long INTERVAL_MS = 30000UL; // 30 seconds

void loop() {
  // Must be called frequently to keep MQTT connection alive and
  // process any incoming messages in the receive buffer.
  if (!mqtt.connected()) connectMQTT();
  mqtt.loop();

  if (WiFi.status() != WL_CONNECTED) connectWiFi();

  if (millis() - lastRun < INTERVAL_MS) return;
  lastRun = millis();

  // -- Read all sensors --------------------------------------------------
  int   moisture = analogReadMoisture();
  float temp     = dht.readTemperature();
  float humidity = dht.readHumidity();
  bool  rain     = (digitalRead(PIN_RAIN_SENSOR) == HIGH);

  // Flow rate from pulse count.
  // YF-S201 spec: 7.5 pulses per second = 1 litre per minute.
  long  pulses     = flowPulseCount;
  flowPulseCount   = 0;
  float flowLitres = (pulses / 7.5f / 60.0f) * (INTERVAL_MS / 1000.0f);

  Serial.printf("[Sensors] moisture=%d temp=%.1f hum=%.1f rain=%d flow=%.3fL\n",
                moisture, temp, humidity, (int)rain, flowLitres);

  // -- Post to Supabase --------------------------------------------------
  postSensorReading(moisture, temp, humidity, rain, flowLitres);
  checkFaultDetection(moisture);

  // -- Irrigation decision -----------------------------------------------
  if (!manualOverride) {
    if (rain) {
      Serial.println("[Irrigation] Rain detected -- skipping");

    } else if (moisture >= cropProfile.moistureHigh) {
      Serial.println("[Irrigation] Soil wet -- no action");

    } else if (moisture >= cropProfile.moistureLow) {
      Serial.println("[Irrigation] Soil OK -- no action");

    } else {
      int rainPct = getRainForecastPct();
      Serial.printf("[Weather] Rain forecast: %d%%\n", rainPct);

      if (rainPct >= cropProfile.rainSkipPct) {
        Serial.println("[Irrigation] Rain forecast -- skipping");
      } else {
        Serial.println("[Irrigation] Starting auto cycle");
        long logId = postPumpLogStart(moisture, "auto");

        pumpRunning = true;
        digitalWrite(PIN_PUMP_RELAY, HIGH);
        delay((unsigned long)cropProfile.irrigateSecs * 1000UL);
        digitalWrite(PIN_PUMP_RELAY, LOW);
        pumpRunning = false;

        int   after     = analogReadMoisture();
        float waterUsed = (cropProfile.irrigateSecs / 60.0f) * 0.5f; // rough estimate
        patchPumpLogEnd(logId, after, cropProfile.irrigateSecs, waterUsed);
        Serial.println("[Irrigation] Cycle complete. Moisture after: " + String(after));
      }
    }
  }

  // -- Fallback: check Supabase device_commands --------------------------
  String cmd = checkDeviceCommands();
  if (cmd == "pump_on" && !pumpRunning) {
    manualOverride = true;
    pumpRunning    = true;
    digitalWrite(PIN_PUMP_RELAY, HIGH);
    Serial.println("[Command] Manual pump ON via Supabase");
  } else if (cmd == "pump_off") {
    manualOverride = false;
    pumpRunning    = false;
    digitalWrite(PIN_PUMP_RELAY, LOW);
    Serial.println("[Command] Manual pump OFF via Supabase");
  }

  updateDeviceStatus("online");
}
