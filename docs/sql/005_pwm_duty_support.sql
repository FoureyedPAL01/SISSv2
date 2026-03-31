-- 005_pwm_duty_support.sql
-- Adds PWM duty cycle support for variable speed pump control
-- Compatible with D4184 MOSFET module

-- Add pwm_duty column to crop_profiles
-- Default 200 = 78% duty cycle (closest to previous relay ON behavior)
ALTER TABLE crop_profiles ADD COLUMN IF NOT EXISTS pwm_duty int DEFAULT 200;

-- Update existing rows to default PWM if not set
UPDATE crop_profiles SET pwm_duty = 200 WHERE pwm_duty IS NULL;

-- Verify the column was added
SELECT column_name, data_type, column_default 
FROM information_schema.columns 
WHERE table_name = 'crop_profiles' AND column_name = 'pwm_duty';