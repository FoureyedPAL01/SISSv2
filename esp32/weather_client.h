// weather_client.h
// SISS v2 -- Fetches rain probability for the next 6 hours from Open-Meteo.
// Open-Meteo is free and open-source -- no API key or account needed.
// Documentation: https://open-meteo.com/en/docs

#pragma once
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include <ArduinoJson.h>
#include "config.h"

// Returns 0 to 100 representing the highest rain probability in the next 6 hours.
// Returns 0 on any network or parse error -- safe default, irrigation will proceed.
int getRainForecastPct() {
  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient http;

  // latitude / longitude: location of the plant
  // hourly=precipitation_probability: one value per hour (0-100%)
  // forecast_days=1: only today's data, keeps response size small
  String url =
    "https://api.open-meteo.com/v1/forecast"
    "?latitude="  + String(LOCATION_LAT) +
    "&longitude=" + String(LOCATION_LON) +
    "&hourly=precipitation_probability"
    "&forecast_days=1";

  http.begin(client, url);
  int code = http.GET();
  if (code != 200) { http.end(); return 0; }

  // Response structure:
  // {
  //   "hourly": {
  //     "time": ["2025-01-01T00:00", ...],
  //     "precipitation_probability": [5, 10, 20, 80, 90, 70, ...]
  //   }
  // }
  // Take the maximum of the first 6 values (next 6 hours).
  JsonDocument doc;
  auto err = deserializeJson(doc, http.getStream());
  http.end();
  if (err) return 0;

  auto probs   = doc["hourly"]["precipitation_probability"];
  int  maxRain = 0;
  for (int i = 0; i < 6 && i < (int)probs.size(); i++) {
    int p = probs[i].as<int>();
    if (p > maxRain) maxRain = p;
  }
  return maxRain;
}
