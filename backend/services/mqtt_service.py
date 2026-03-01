import json
import asyncio
import paho.mqtt.client as mqtt
from pydantic import BaseModel, ValidationError
from typing import Optional
from database import supabase
from config import settings

class SensorData(BaseModel):
    device_id: str
    soil_pct: float
    temp_c: Optional[float] = None
    humidity: Optional[float] = None
    rain: bool
    flow_litres: float

# This needs to be async-aware or at least offload to thread, but paho is synchronous.
# For simplicity and robust long-running ingestion, we bridge the paho callbacks context to Supabase synchronously.
# supabase-py uses httpx under the hood which can be sync or async depending on the method.
# By default, client.table().insert().execute() is synchronous.

def on_connect(client, userdata, flags, rc, properties=None):
    if rc == 0:
        print("Connected to MQTT Broker!")
        client.subscribe("devices/+/sensors")
    else:
        print(f"Failed to connect to MQTT broker, return code {rc}")

def on_message(client, userdata, msg):
    print(f"Received message on topic {msg.topic}")
    try:
        payload = json.loads(msg.payload.decode("utf-8"))
        
        # Validate data using Pydantic
        sensor_data = SensorData(**payload)
        
        # Insert into Supabase
        # RLS bypass relies on the SERVICE_ROLE_KEY used in main.supabase initialization
        data, count = supabase.table("sensor_readings").insert({
            "device_id": sensor_data.device_id,
            "soil_moisture": sensor_data.soil_pct,
            "temperature_c": sensor_data.temp_c,
            "humidity": sensor_data.humidity,
            "rain_detected": sensor_data.rain,
            "flow_litres": sensor_data.flow_litres
        }).execute()
        
        print(f"Successfully inserted reading for {sensor_data.device_id}")

    except json.JSONDecodeError:
        print("Error decoding MQTT payload as JSON")
    except ValidationError as e:
        print(f"Validation error for incoming sensor data: {e}")
    except Exception as e:
        print(f"Unexpected error processing MQTT message: {e}")

# Create an MQTT client
mqtt_client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
mqtt_client.on_connect = on_connect
mqtt_client.on_message = on_message

def start_mqtt_client():
    mqtt_client.connect(settings.MQTT_BROKER, settings.MQTT_PORT, 60)
    # loop_start() runs the network loop in a background thread
    mqtt_client.loop_start()

def stop_mqtt_client():
    mqtt_client.loop_stop()
    mqtt_client.disconnect()
