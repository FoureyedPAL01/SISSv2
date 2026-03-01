from datetime import datetime, timezone
from services.weather_service import get_weather_forecast
from services.pump_service import send_pump_command
from database import supabase

async def evaluate_irrigation_needs(device_id: str, current_moisture: float, lat: float, lon: float):
    """
    Evaluates whether the pump should be turned on based on current moisture, ET, and weather.
    """
    # 1. Fetch active crop profile for device (if any)
    # Default fallback thresholds
    dry_threshold = 30.0
    
    # Ideally, fetch from Supabase
    try:
        res, count = supabase.table("devices").select("*, crop_profiles(*)").eq("id", device_id).execute()
        if res and res[1] and len(res[1]) > 0:
            device_data = res[1][0]
            if "crop_profiles" in device_data and device_data["crop_profiles"]:
                dry_threshold = device_data["crop_profiles"].get("min_moisture", 30.0)
    except Exception as e:
        print(f"Could not fetch crop profile: {e}")

    # 2. If moisture is well above dry threshold, no need to water
    if current_moisture >= (dry_threshold + 5.0):
        return

    # 3. Moisture is low... check weather forecast
    forecast = await get_weather_forecast(lat, lon)
    
    if forecast:
        # If it's going to rain a lot soon, let nature handle it
        if forecast.get("will_rain_soon"):
            print(f"Skipping irrigation for {device_id}: high chance of rain in next 12h.")
            return
            
        # Simplified Hargreaves ET Logic
        # ET0 = 0.0023 * Ra * (Tmean + 17.8) * sqrt(Tmax - Tmin)
        # Without Ra (solar radiation, which depends on latitude and day of year), 
        # we adjust pump duration based purely on the temperature differential.
        t_max = forecast.get("temp_max")
        t_min = forecast.get("temp_min")
        
        if t_max is not None and t_min is not None:
            t_mean = (t_max + t_min) / 2
            # Simplified proxy for ET intensity
            et_proxy = (t_mean + 17.8) * ((t_max - t_min) ** 0.5)
            print(f"ET proxy calculated: {et_proxy:.2f}")
            # In a real system, you'd calculate exact mm/day water loss here.

    # 4. We need to irrigate
    if current_moisture < dry_threshold:
        print(f"Moisture ({current_moisture}%) below threshold ({dry_threshold}%). Watering.")
        send_pump_command(device_id, "pump_on", source="automated")
        # Note: The ESP32 firmware handles turning the pump OFF when it reaches the wet threshold,
        # or after the 30 minute safety timeout.
