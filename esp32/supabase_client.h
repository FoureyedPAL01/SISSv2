// supabase_client.h
// SISS v2 -- All HTTPS calls to the Supabase REST API.
//
// How Supabase REST works:
//   Every table is exposed at: <SUPABASE_URL>/rest/v1/<table_name>
//   GET   = SELECT (add ?column=eq.value to filter rows)
//   POST  = INSERT a new row
//   PATCH = UPDATE matching rows (?id=eq.<value> targets one row)
//   Headers: apikey identifies the project; Authorization sets RLS permissions
//   Prefer: return=representation makes POST return the inserted row as JSON

#pragma once
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include <ArduinoJson.h>
#include "config.h"

// Attaches the three required headers to every Supabase request
void _addSupabaseHeaders(HTTPClient& http) {
  http.addHeader("apikey",        SUPABASE_ANON_KEY);
  http.addHeader("Authorization", "Bearer " + String(SUPABASE_ANON_KEY));
  http.addHeader("Content-Type",  "application/json");
  http.addHeader("Prefer",        "return=representation");
}

// POST a sensor reading row. Returns true on success (HTTP 201).
bool postSensorReading(int moisture, float temp, float humidity,
                       bool rain, float flow) {
  WiFiClientSecure client;
  client.setInsecure(); // skips TLS cert verification; acceptable for academic use
  HTTPClient http;
  http.begin(client, String(SUPABASE_URL) + "/rest/v1/sensor_readings");
  _addSupabaseHeaders(http);

  JsonDocument doc;
  doc["device_id"]     = DEVICE_ID;
  doc["soil_moisture"] = moisture;
  doc["temperature_c"] = temp;
  doc["humidity"]      = humidity;
  doc["rain_detected"] = rain;
  doc["flow_litres"]   = flow;
  String body;
  serializeJson(doc, body);

  int code = http.POST(body);
  http.end();
  return (code == 201);
}

// POST the start of a pump cycle.
// Returns the database-assigned id of the new row (needed to PATCH it later).
// Returns -1 on failure.
long postPumpLogStart(int moistureBefore, String triggerType) {
  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient http;
  http.begin(client, String(SUPABASE_URL) + "/rest/v1/pump_logs");
  _addSupabaseHeaders(http);

  JsonDocument doc;
  doc["device_id"]       = DEVICE_ID;
  doc["moisture_before"] = moistureBefore;
  doc["trigger_type"]    = triggerType;
  String body;
  serializeJson(doc, body);

  int    code = http.POST(body);
  String resp = http.getString();
  http.end();
  if (code != 201) return -1;

  // Supabase returns the inserted row as a JSON array:
  // [{"id":42, "device_id":"...", "moisture_before":35, ...}]
  // We parse it to extract the id for the later PATCH call.
  JsonDocument respDoc;
  deserializeJson(respDoc, resp);
  return respDoc[0]["id"].as<long>();
}

// PATCH the pump log row when the irrigation cycle ends.
// logId: the id returned by postPumpLogStart.
void patchPumpLogEnd(long logId, int moistureAfter,
                     int durationSecs, float waterLitres) {
  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient http;
  // ?id=eq.<logId> is a Supabase REST filter: WHERE id = logId
  http.begin(client, String(SUPABASE_URL) +
             "/rest/v1/pump_logs?id=eq." + String(logId));
  http.addHeader("apikey",        SUPABASE_ANON_KEY);
  http.addHeader("Authorization", "Bearer " + String(SUPABASE_ANON_KEY));
  http.addHeader("Content-Type",  "application/json");

  JsonDocument doc;
  doc["moisture_after"]    = moistureAfter;
  doc["duration_seconds"]  = durationSecs;
  doc["water_used_litres"] = waterLitres;
  String body;
  serializeJson(doc, body);

  http.PATCH(body);
  http.end();
}

// Struct to hold thresholds loaded from Supabase
struct CropProfile {
  int moistureLow  = DEFAULT_MOISTURE_LOW;
  int moistureHigh = DEFAULT_MOISTURE_HIGH;
  int irrigateSecs = DEFAULT_IRRIGATE_SECS;
  int rainSkipPct  = DEFAULT_RAIN_SKIP_PCT;
};

// GET active crop profile from Supabase.
// cropProfileId: the bigint id of the crop_profiles row.
// Returns a struct with defaults if no profile is set or the fetch fails.
CropProfile fetchCropProfile(String cropProfileId) {
  CropProfile p;
  if (cropProfileId == "" || cropProfileId == "null") return p;

  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient http;
  http.begin(client, String(SUPABASE_URL) +
             "/rest/v1/crop_profiles?id=eq." + cropProfileId + "&limit=1");
  http.addHeader("apikey",        SUPABASE_ANON_KEY);
  http.addHeader("Authorization", "Bearer " + String(SUPABASE_ANON_KEY));

  if (http.GET() == 200) {
    JsonDocument doc;
    deserializeJson(doc, http.getString());
    if (doc.size() > 0) {
      p.moistureLow  = doc[0]["moisture_threshold_low"].as<int>();
      p.moistureHigh = doc[0]["moisture_threshold_high"].as<int>();
      p.irrigateSecs = doc[0]["irrigation_duration_s"].as<int>();
      p.rainSkipPct  = doc[0]["weather_sensitivity"].as<int>();
    }
  }
  http.end();
  return p;
}

// INSERT an alert row when the ESP32 detects a fault.
void insertAlert(String alertType, String message) {
  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient http;
  http.begin(client, String(SUPABASE_URL) + "/rest/v1/alerts");
  _addSupabaseHeaders(http);

  JsonDocument doc;
  doc["device_id"]  = DEVICE_ID;
  doc["alert_type"] = alertType;
  doc["message"]    = message;
  String body;
  serializeJson(doc, body);

  http.POST(body);
  http.end();
}

// Poll device_commands for unconsumed manual commands from Flutter.
// Returns "pump_on", "pump_off", or "" if nothing is pending.
// Immediately marks the found row consumed=true to prevent re-execution.
String checkDeviceCommands() {
  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient http;
  http.begin(client, String(SUPABASE_URL) +
             "/rest/v1/device_commands"
             "?device_id=eq." + String(DEVICE_ID) +
             "&consumed=eq.false"
             "&order=created_at.asc"
             "&limit=1");
  http.addHeader("apikey",        SUPABASE_ANON_KEY);
  http.addHeader("Authorization", "Bearer " + String(SUPABASE_ANON_KEY));

  String result = "";
  if (http.GET() == 200) {
    JsonDocument doc;
    deserializeJson(doc, http.getString());
    if (doc.size() > 0) {
      result     = doc[0]["command"].as<String>();
      long cmdId = doc[0]["id"].as<long>();
      http.end();

      // Mark consumed immediately
      HTTPClient patchHttp;
      patchHttp.begin(client, String(SUPABASE_URL) +
                      "/rest/v1/device_commands?id=eq." + String(cmdId));
      patchHttp.addHeader("apikey",        SUPABASE_ANON_KEY);
      patchHttp.addHeader("Authorization", "Bearer " + String(SUPABASE_ANON_KEY));
      patchHttp.addHeader("Content-Type",  "application/json");
      patchHttp.PATCH("{\"consumed\":true}");
      patchHttp.end();
      return result;
    }
  }
  http.end();
  return result;
}

// PATCH devices.status and devices.last_seen.
// Called at boot (status="online") and every loop iteration.
void updateDeviceStatus(String status) {
  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient http;
  http.begin(client, String(SUPABASE_URL) +
             "/rest/v1/devices?id=eq." + String(DEVICE_ID));
  http.addHeader("apikey",        SUPABASE_ANON_KEY);
  http.addHeader("Authorization", "Bearer " + String(SUPABASE_ANON_KEY));
  http.addHeader("Content-Type",  "application/json");
  // "now()" is resolved by PostgreSQL to the current server timestamp
  http.PATCH("{\"status\":\"" + status + "\",\"last_seen\":\"now()\"}");
  http.end();
}
