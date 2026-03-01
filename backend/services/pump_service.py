import paho.mqtt.client as mqtt
import json
from database import supabase
from config import settings

def send_pump_command(device_id: str, command: str, source: str = "automated"):
    """
    command: 'pump_on' or 'pump_off'
    source: 'automated' (decision engine) or 'manual' (user override via app)
    """
    if command not in ["pump_on", "pump_off"]:
        print(f"Invalid command: {command}")
        return False

    topic = f"devices/{device_id}/control"
    payload = json.dumps({"cmd": command})
    
    # We use a temporary publish-only client here for simplicity, 
    # but in a high-throughput system you'd reuse the existing one.
    try:
        # Publish
        client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
        client.connect(settings.MQTT_BROKER, settings.MQTT_PORT, 60)
        client.publish(topic, payload)
        client.disconnect()
        
        # Log to Supabase
        action = "ON" if command == "pump_on" else "OFF"
        supabase.table("pump_logs").insert({
            "device_id": device_id,
            "action": action,
            "source": source
        }).execute()
        
        print(f"Successfully commanded {device_id} pump {action}")
        return True
        
    except Exception as e:
        print(f"Error sending pump command to {device_id}: {e}")
        return False
