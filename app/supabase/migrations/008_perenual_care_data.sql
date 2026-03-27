-- 008_perenual_care_data.sql
-- Adds a column to store Perenual care guide data (includes fertilizer info).

alter table public.crop_profiles
  add column if not exists perenual_care_data jsonb;
