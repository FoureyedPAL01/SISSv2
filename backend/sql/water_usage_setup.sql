-- Run this in Supabase SQL Editor to create water_usage tracking table

-- 1. Create the water_usage table
CREATE TABLE IF NOT EXISTS water_usage (
    id SERIAL PRIMARY KEY,
    device_id UUID REFERENCES devices(id) ON DELETE CASCADE,
    date DATE NOT NULL DEFAULT CURRENT_DATE,
    total_liters FLOAT DEFAULT 0,
    reading_count INT DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(device_id, date)
);

-- 2. Create index for faster queries
CREATE INDEX IF NOT EXISTS idx_water_usage_device_date 
ON water_usage(device_id, date DESC);

-- 3. Enable RLS
ALTER TABLE water_usage ENABLE ROW LEVEL SECURITY;

-- 4. Create policy (users can only see their own device's data)
CREATE POLICY "Users can view own device water usage" 
ON water_usage FOR SELECT
USING (
    device_id IN (
        SELECT id FROM devices 
        WHERE user_id = auth.uid()
    )
);

-- 5. Create function to aggregate daily water usage from sensor_readings
CREATE OR REPLACE FUNCTION aggregate_water_usage()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    rec RECORD;
    prev_device_id UUID;
    prev_flow FLOAT := 0;
    curr_flow FLOAT := 0;
    daily_diff FLOAT := 0;
BEGIN
    -- Reset for new batch
    prev_device_id := NULL;
    prev_flow := 0;
    
    -- Process all sensor readings ordered by device and time
    FOR rec IN 
        SELECT device_id, flow_litres, recorded_at
        FROM sensor_readings
        WHERE flow_litres IS NOT NULL
        ORDER BY device_id, recorded_at
    LOOP
        -- If new device, reset counter
        IF prev_device_id IS NULL OR prev_device_id != rec.device_id THEN
            prev_device_id := rec.device_id;
            prev_flow := rec.flow_litres;
        END IF;
        
        -- Calculate difference (handle counter reset)
        IF rec.flow_litres >= prev_flow THEN
            daily_diff := rec.flow_litres - prev_flow;
        ELSE
            -- Counter was reset, assume it's a new reading
            daily_diff := rec.flow_litres;
        END IF;
        
        -- Only count positive differences
        IF daily_diff > 0 THEN
            -- Update or insert daily total
            INSERT INTO water_usage (device_id, date, total_liters, reading_count)
            VALUES (rec.device_id, rec.recorded_at::date, daily_diff, 1)
            ON CONFLICT (device_id, date) 
            DO UPDATE SET 
                total_liters = water_usage.total_liters + EXCLUDED.total_liters,
                reading_count = water_usage.reading_count + 1;
        END IF;
        
        prev_flow := rec.flow_litres;
    END LOOP;
END;
$$;

-- 6. Create scheduled job to run aggregation (if you have pg_cron extension)
-- Or call the function manually after each sensor reading

-- 7. Simple function to get daily usage for a device
CREATE OR REPLACE FUNCTION get_daily_water_usage(
    p_device_id UUID,
    p_days INTEGER DEFAULT 7
)
RETURNS TABLE(date DATE, total_liters FLOAT)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT wu.date, wu.total_liters
    FROM water_usage wu
    WHERE wu.device_id = p_device_id
    AND wu.date >= CURRENT_DATE - (p_days - 1) * INTERVAL '1 day'
    ORDER BY wu.date ASC;
END;
$$;
