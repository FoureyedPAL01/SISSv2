from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from services.pump_service import send_pump_command
from services.weather_service import get_weather_forecast
from services.water_usage_service import get_weekly_water_usage

router = APIRouter()

class PumpRequest(BaseModel):
    device_id: str
    command: str  # 'pump_on' or 'pump_off'

@router.post("/pump/toggle")
async def toggle_pump(req: PumpRequest):
    """
    Manually overrides the pump state (e.g., from the Flutter App).
    """
    if req.command not in ["pump_on", "pump_off"]:
        raise HTTPException(status_code=400, detail="Invalid command")
        
    success = send_pump_command(req.device_id, req.command, source="manual")
    if success:
        return {"status": "success", "message": f"Command {req.command} sent to {req.device_id}"}
    else:
        raise HTTPException(status_code=500, detail="Failed to send command to device")

@router.get("/weather/current")
async def get_current_weather(lat: float, lon: float):
    """
    Fetches the latest parsed forecast for the Flutter Dashboard.
    """
    forecast = await get_weather_forecast(lat, lon)
    if not forecast:
        raise HTTPException(status_code=500, detail="Failed to fetch weather data")
    return forecast

@router.get("/water/usage")
async def get_water_usage(device_id: str, days: int = 7):
    """
    Fetches weekly water usage for a device.
    Returns list of {date, total_liters} for each day.
    """
    if days < 1 or days > 30:
        raise HTTPException(status_code=400, detail="Days must be between 1 and 30")
    
    usage = await get_weekly_water_usage(device_id, days)
    return {"device_id": device_id, "days": days, "usage": usage}
