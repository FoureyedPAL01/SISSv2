-- supabase/migrations/20260309_purge_logs_cron.sql

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Remove existing job if it exists
select cron.unschedule('purge-old-pump-logs')
where exists (
  select 1 from cron.job where jobname = 'purge-old-pump-logs'
);

-- Schedule daily at 02:00 UTC
-- Replace YOUR_SERVICE_ROLE_KEY with the actual key from Supabase Dashboard → Settings → API
select cron.schedule(
  'purge-old-pump-logs',
  '0 2 * * *',
  $$
    select net.http_post(
      url     := 'https://ruzjwxbwknpxndxfxtig.supabase.co/functions/v1/purge-old-logs',
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ1emp3eGJ3a25weG5keGZ4dGlnIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3MjU5NDMxOSwiZXhwIjoyMDg4MTcwMzE5fQ.Kco7MDZMybjp2dA2Yy3T-xO_mWGqmK5fFFIWINMaitE'
      ),
      body    := '{}'::jsonb
    )
  $$
);
