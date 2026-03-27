-- 007_unit_preferences.sql
-- Adds wind, precipitation, and AQI unit preference columns to users.

alter table public.users
  add column if not exists wind_unit          text default 'km/h',
  add column if not exists precipitation_unit text default 'mm',
  add column if not exists aqi_type           text default 'us';
