// supabase_client.h
#pragma once
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include <ArduinoJson.h>
#include "config.h"

struct CropProfile {
  int moistureLow;
  int irrigateSecs;
  int rainSkipPct;
};

void _addSupabaseHeaders(HTTPClient& http) {
  http.addHeader("apikey", SUPABASE_ANON_KEY);
  http.addHeader("Authorization", "Bearer " + String(SUPABASE_ANON_KEY));
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Prefer", "return=representation");
}

// Perfectly maps to: sensor_readings table
void postSensorReading(int moisture, float temp, float humidity, bool rain, float flow) {
  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient http;
  http.begin(client, String(SUPABASE_URL) + "/rest/v1/sensor_readings");
  _addSupabaseHeaders(http);

  JsonDocument doc;
  doc["device_id"] = DEVICE_ID;
  doc["soil_moisture"] = moisture;
  doc["temperature_c"] = temp;
  doc["humidity"] = humidity;
  doc["rain_detected"] = rain;
  doc["flow_litres"] = flow;

  String payload;
  serializeJson(doc, payload);
  http.POST(payload);
  http.end();
}

// Perfectly maps to: pump_logs table
long postPumpLogStart(int moistureBefore, String triggerType) {
  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient http;
  http.begin(client, String(SUPABASE_URL) + "/rest/v1/pump_logs");
  _addSupabaseHeaders(http);

  JsonDocument doc;
  doc["device_id"] = DEVICE_ID;
  doc["moisture_before"] = moistureBefore;
  doc["trigger_type"] = triggerType; // 'auto' or 'manual'

  String payload;
  serializeJson(doc, payload);
  
  long logId = -1;
  if (http.POST(payload) == 201) {
    JsonDocument resDoc;
    deserializeJson(resDoc, http.getString());
    logId = resDoc[0]["id"].as<long>();
  }
  http.end();
  return logId;
}

// Perfectly maps to: pump_logs table updates
void patchPumpLogEnd(long logId, int moistureAfter, int durationSecs, float waterUsed) {
  if (logId < 0) return;
  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient http;
  http.begin(client, String(SUPABASE_URL) + "/rest/v1/pump_logs?id=eq." + String(logId));
  _addSupabaseHeaders(http);

  JsonDocument doc;
  doc["moisture_after"] = moistureAfter;
  doc["duration_seconds"] = durationSecs;
  doc["water_used_litres"] = waterUsed;

  String payload;
  serializeJson(doc, payload);
  http.PATCH(payload);
  http.end();
}

// Relational Fetch: Gets crop_profiles data directly through the device relation!
CropProfile fetchCropProfile() {
  CropProfile profile = {DEFAULT_MOISTURE_LOW, DEFAULT_IRRIGATE_SEC, DEFAULT_RAIN_SKIP};
  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient http;
  
  String url = String(SUPABASE_URL) + "/rest/v1/devices?id=eq." + String(DEVICE_ID) + "&select=crop_profiles(moisture_threshold_low,irrigation_duration_s,weather_sensitivity)";
  http.begin(client, url);
  _addSupabaseHeaders(http);

  if (http.GET() == 200) {
    JsonDocument doc;
    deserializeJson(doc, http.getString());
    if (doc.size() > 0 && !doc[0]["crop_profiles"].isNull()) {
      profile.moistureLow = doc[0]["crop_profiles"]["moisture_threshold_low"].as<int>();
      profile.irrigateSecs = doc[0]["crop_profiles"]["irrigation_duration_s"].as<int>();
      profile.rainSkipPct = doc[0]["crop_profiles"]["weather_sensitivity"].as<int>();
    }
  }
  http.end();
  return profile;
}

void updateDeviceStatus(String status) {
  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient http;
  http.begin(client, String(SUPABASE_URL) + "/rest/v1/devices?id=eq." + String(DEVICE_ID));
  _addSupabaseHeaders(http);
  http.PATCH("{\"status\":\"" + status + "\"}");
  http.end();
}
