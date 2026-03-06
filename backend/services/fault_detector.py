import asyncio
from datetime import datetime, timezone, timedelta
from database import supabase

async def run_fault_checks():
    """
    Background task to scan for faulty sensors or offline devices.
    """
    try:
        # Check 1: Offline devices (No data for >15 mins)
        fifteen_mins_ago = (datetime.now(timezone.utc) - timedelta(minutes=15)).isoformat()
        
        # In Supabase, you'd typically query the last reading per device
        # For simplicity in this demo, we assume there's a view or we check the latest reading per device
        res = supabase.table("devices").select("id, last_seen").execute()
        if res and res.data:
            for device in res.data:
                last_seen_str = device.get("last_seen")
                if not last_seen_str:
                    continue
                
                # Compare timestamps
                last_seen = datetime.fromisoformat(last_seen_str.replace("Z", "+00:00"))
                if last_seen < datetime.now(timezone.utc) - timedelta(minutes=15):
                    log_fault(device["id"], "OFFLINE", f"Device hasn't reported data since {last_seen_str}")

        # Check 2: Pump stuck ON (Pump log says ON, but no OFF within 35 mins)
        # The ESP32 max runtime is 30 mins, so if it's been 35, something is wrong with logging or control
        # (Implementation of this specific SQL query omitted for brevity, 
        # but would check if the last log for the device was 'ON' > 35m ago)

    except Exception as e:
        print(f"Error running fault checks: {e}")

def log_fault(device_id: str, current_state: str, details: str):
    print(f"FAULT DETECTED [{device_id}] - {current_state}: {details}")
    try:
        supabase.table("system_alerts").insert({
            "device_id": device_id,
            "alert_type": current_state,
            "message": details,
            "status": "active"
        }).execute()
        # This insertion could trigger a Postgres trigger -> Edge Function -> Push notification
    except Exception as e:
        print(f"Could not log fault to Supabase: {e}")

async def fault_detector_loop():
    while True:
        await run_fault_checks()
        await asyncio.sleep(300) # Run every 5 minutes
