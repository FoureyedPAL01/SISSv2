from database import supabase
from typing import List, Dict, Any, Optional
from datetime import datetime, timedelta

async def get_weekly_water_usage(device_id: str, days: int = 7) -> List[Dict[str, Any]]:
    """
    Fetches weekly water usage for a device.
    Returns a list of {date, total_liters} for each day.
    """
    try:
        # Calculate date range
        end_date = datetime.now().date()
        start_date = end_date - timedelta(days=days - 1)
        
        # Query water_usage table
        response = supabase.table('water_usage').select(
            'date, total_liters'
        ).eq(
            'device_id', device_id
        ).gte(
            'date', start_date.isoformat()
        ).lte(
            'date', end_date.isoformat()
        ).order(
            'date', ascending=True
        ).execute()
        
        if not response.data:
            # Return empty data for each day
            return _generate_empty_days(days)
        
        # Create a map of existing data
        usage_map = {
            datetime.strptime(row['date'], '%Y-%m-%d').date(): row['total_liters']
            for row in response.data
        }
        
        # Fill in missing days with 0
        result = []
        for i in range(days):
            day = start_date + timedelta(days=i)
            result.append({
                'date': day.isoformat(),
                'total_liters': usage_map.get(day, 0.0)
            })
        
        return result
        
    except Exception as e:
        print(f"Error fetching water usage: {e}")
        return _generate_empty_days(days)

def _generate_empty_days(days: int) -> List[Dict[str, Any]]:
    """Generate empty data for each day in the range."""
    end_date = datetime.now().date()
    start_date = end_date - timedelta(days=days - 1)
    return [
        {
            'date': (start_date + timedelta(days=i)).isoformat(),
            'total_liters': 0.0
        }
        for i in range(days)
    ]

def aggregate_water_usage():
    """
    Triggers water usage aggregation from sensor_readings.
    Can be called periodically or after sensor data ingestion.
    """
    try:
        # Call the database function to aggregate
        result = supabase.rpc('aggregate_water_usage').execute()
        print(f"Water usage aggregation completed: {result.data}")
        return True
    except Exception as e:
        print(f"Error aggregating water usage: {e}")
        return False
