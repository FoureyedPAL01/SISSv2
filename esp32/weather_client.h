// weather_client.h
#pragma once
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include <ArduinoJson.h>
#include "config.h"

int getRainForecastPct() {
  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient http;

  String url = "https://api.open-meteo.com/v1/forecast?latitude=" + String(LOCATION_LAT) + "&longitude=" + String(LOCATION_LON) + "&hourly=precipitation_probability&forecast_days=1";
  http.begin(client, url);
  
  int maxProb = 0;
  if (http.GET() == 200) {
    JsonDocument doc;
    deserializeJson(doc, http.getString());
    JsonArray probs = doc["hourly"]["precipitation_probability"].as<JsonArray>();
    
    for (int i = 0; i < 6 && i < probs.size(); i++) {
      int p = probs[i].as<int>();
      if (p > maxProb) maxProb = p;
    }
  }
  http.end();
  return maxProb;
}
