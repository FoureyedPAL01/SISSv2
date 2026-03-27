-- 006_user_location.sql
-- Adds editable location fields to the users table.
-- Used by the Flutter app for weather API calls.

alter table public.users
  add column if not exists location_lat text default '19.0760',
  add column if not exists location_lon text default '72.8777';
