from fastapi import FastAPI
from database import supabase
import uvicorn

app = FastAPI(title="Smart Irrigation Backend")

from api.routes import router as api_router
app.include_router(api_router, prefix="/api")

import asyncio

@app.on_event("startup")
async def startup_event():
    from services.mqtt_service import start_mqtt_client
    from services.fault_detector import fault_detector_loop
    
    start_mqtt_client()
    asyncio.create_task(fault_detector_loop())
    print("Backend starting up, MQTT listener and Fault Detector initialized...")

@app.on_event("shutdown")
async def shutdown_event():
    from services.mqtt_service import stop_mqtt_client
    stop_mqtt_client()
    print("Backend shutting down, MQTT listener stopped.")

@app.get("/health")
async def health_check():
    return {"status": "ok", "message": "Smart Irrigation Backend is running"}

if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
