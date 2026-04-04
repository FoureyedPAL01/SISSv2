# Supabase Edge Functions

This document contains all Edge Functions used in the RootSync project.

---

## Table of Contents

1. [perenual-lookup](#perenual-lookup)
2. [weekly-summary](#weekly-summary)
3. [purge-old-logs](#purge-old-logs)
4. [send-alert-notification](#send-alert-notification)

---

## perenual-lookup

Fetches plant information from the Perenual API and caches it in the database.

### Purpose
- Lookup plant species data by name
- Cache results for 7 days to reduce API calls
- Retrieve care guides (fertilizer, watering, sunlight, pruning)

### Environment Variables
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `PERENUAL_API_KEY`

### Request Body
```json
{
  "profile_id": "uuid",
  "plant_name": "string"
}
```

### Response
```json
{
  "ok": true,
  "data": { ... },
  "care_data": { ... },
  "source": "cache" | "api"
}
```

### Source Code

```typescript
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { profile_id, plant_name } = await req.json();

    if (!profile_id || !plant_name) {
      return new Response(
        JSON.stringify({ ok: false, error: "profile_id and plant_name are required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // ── Check cache ──────────────────────────────────────────────────────────
    const { data: profile, error: fetchErr } = await supabase
      .from("crop_profiles")
      .select("perenual_cached_at, perenual_data, perenual_care_data")
      .eq("id", profile_id)
      .single();

    if (fetchErr) throw fetchErr;

    const SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000;
    const cachedAt      = profile?.perenual_cached_at
      ? new Date(profile.perenual_cached_at).getTime()
      : 0;
    const isFresh = Date.now() - cachedAt < SEVEN_DAYS_MS;

    if (isFresh && profile?.perenual_data && profile?.perenual_care_data) {
      return new Response(
        JSON.stringify({
          ok:        true,
          data:      profile.perenual_data,
          care_data: profile.perenual_care_data,
          source:    "cache",
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // ── Fetch species from Perenual ──────────────────────────────────────────
    const apiKey = Deno.env.get("PERENUAL_API_KEY");
    if (!apiKey) throw new Error("PERENUAL_API_KEY secret not set");

    const speciesUrl =
      `https://perenual.com/api/species-list?key=${apiKey}&q=${encodeURIComponent(plant_name)}`;
    const speciesRes  = await fetch(speciesUrl);
    if (!speciesRes.ok) throw new Error(`Perenual species error: ${speciesRes.status}`);

    const speciesJson = await speciesRes.json();
    const species     = speciesJson?.data?.[0];

    if (!species) {
      return new Response(
        JSON.stringify({ ok: false, error: `No results found for "${plant_name}"` }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const plantData = {
      id:              species.id,
      common_name:     species.common_name,
      scientific_name: species.scientific_name?.[0] ?? null,
      watering:        species.watering,
      sunlight:        species.sunlight,
      cycle:           species.cycle,
      image_url:       species.default_image?.medium_url ?? null,
      description:     species.description ?? null,
    };

    // ── Fetch care guide for fertilizer info ─────────────────────────────────
    const careUrl =
      `https://perenual.com/api/care-guide-list?key=${apiKey}&species_id=${species.id}`;
    const careRes = await fetch(careUrl);

    let careData: Record<string, unknown> = {};

    if (careRes.ok) {
      const careJson  = await careRes.json();
      const careGuide = careJson?.data?.[0];

      if (careGuide) {
        const sections: Record<string, unknown>[] =
          careGuide.section ?? [];

        const findSection = (type: string) =>
          sections.find(
            (s: Record<string, unknown>) =>
              (s.type as string)?.toLowerCase() === type.toLowerCase(),
          );

        const fertSection   = findSection("fertilizer");
        const waterSection  = findSection("watering");
        const sunSection    = findSection("sunlight");
        const pruneSection  = findSection("pruning");

        careData = {
          fertilizer: fertSection
            ? {
                description: fertSection.description ?? null,
              }
            : null,
          watering: waterSection
            ? { description: waterSection.description ?? null }
            : null,
          sunlight: sunSection
            ? { description: sunSection.description ?? null }
            : null,
          pruning: pruneSection
            ? { description: pruneSection.description ?? null }
            : null,
          fetched_at: new Date().toISOString(),
        };
      }
    }

    // ── Persist to database ──────────────────────────────────────────────────
    const { error: updateErr } = await supabase
      .from("crop_profiles")
      .update({
        perenual_species_id: species.id,
        perenual_data:       plantData,
        perenual_care_data:  careData,
        perenual_cached_at:  new Date().toISOString(),
      })
      .eq("id", profile_id);

    if (updateErr) throw updateErr;

    return new Response(
      JSON.stringify({ ok: true, data: plantData, care_data: careData, source: "api" }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ ok: false, error: String(err) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
```

---

## weekly-summary

Generates and sends weekly summary emails to users with weekly summary enabled.

### Purpose
- Aggregate water usage data for the week
- Calculate percentage change from previous week
- Count alerts generated during the week
- Report device online/offline status
- Send HTML email summary to users

### Environment Variables
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`

### Trigger
- Scheduled via pg_cron (daily)
- Checks if it's Monday in user's timezone before sending

### Data Collected
- Total water used this week (liters)
- Previous week total for comparison
- Daily breakdown chart data
- Alert count
- Device status (online/total)

### Source Code

```typescript
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const supabase = createClient(supabaseUrl, supabaseKey);

interface UserProfile {
  user_id: string;
  email: string;
  timezone: string;
  weekly_summary: boolean;
}

interface WeeklyData {
  totalWaterUsed: number;
  previousWeekTotal: number;
  dailyBreakdown: { date: string; total: number }[];
  alertsCount: number;
  devicesOnline: number;
  devicesTotal: number;
}

Deno.serve(async (req) => {
  try {
    // Get all users with weekly_summary enabled
    const { data: profiles, error: profileError } = await supabase
      .from('user_profiles')
      .select('user_id, timezone, weekly_summary')
      .eq('weekly_summary', true);

    if (profileError) {
      console.error('Error fetching profiles:', profileError);
      return new Response(JSON.stringify({ error: profileError.message }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    if (!profiles || profiles.length === 0) {
      return new Response(JSON.stringify({ message: 'No users with weekly summary enabled' }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const results = [];

    for (const profile of profiles as UserProfile[]) {
      try {
        // Get user's email from auth.users
        const { data: userData, error: userError } = await supabase.auth.admin.getUserById(profile.user_id);
        
        if (userError || !userData.user) {
          console.error(`Error fetching user ${profile.user_id}:`, userError);
          continue;
        }

        const userEmail = userData.user.email;
        const timezone = profile.timezone || 'UTC';

        // Check if today is Monday in user's timezone
        const now = new Date();
        const userDateStr = now.toLocaleString('en-US', { timeZone: timezone });
        const userDate = new Date(userDateStr);
        
        // If it's not Monday, skip (daily cron checks every day)
        if (userDate.getDay() !== 1) {
          continue;
        }

        // Get weekly data
        const weeklyData = await getWeeklyData(profile.user_id, timezone);
        
        if (!weeklyData) {
          // No data this week - skip sending but don't error
          results.push({ userId: profile.user_id, status: 'skipped', reason: 'no_data' });
          continue;
        }

        // Send email (using Supabase's built-in or external SMTP)
        await sendWeeklyEmail(userEmail!, weeklyData, timezone);
        
        results.push({ userId: profile.user_id, status: 'sent' });
      } catch (userError) {
        console.error(`Error processing user ${profile.user_id}:`, userError);
        results.push({ userId: profile.user_id, status: 'error', error: String(userError) });
      }
    }

    return new Response(JSON.stringify({ 
      message: 'Weekly summary processing complete',
      results 
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });

  } catch (error) {
    console.error('Unexpected error:', error);
    return new Response(JSON.stringify({ error: String(error) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});

async function getWeeklyData(userId: string, timezone: string): Promise<WeeklyData | null> {
  // Get devices for user
  const { data: devices } = await supabase
    .from('devices')
    .select('id, name, status')
    .eq('user_id', userId);

  if (!devices || devices.length === 0) {
    return null;
  }

  const deviceIds = devices.map(d => d.id);
  const devicesOnline = devices.filter(d => d.status === 'online').length;

  // Get water usage for this week and last week
  const now = new Date();
  const weekStart = new Date(now);
  weekStart.setDate(weekStart.getDate() - weekStart.getDay()); // Start of current week (Sunday)
  weekStart.setHours(0, 0, 0, 0);

  const lastWeekStart = new Date(weekStart);
  lastWeekStart.setDate(lastWeekStart.getDate() - 7);

  // Query this week's water usage
  const { data: thisWeekData } = await supabase
    .from('sensor_readings')
    .select('recorded_at, flow_litres')
    .in('device_id', deviceIds)
    .gte('recorded_at', weekStart.toISOString())
    .not('flow_litres', 'is', null);

  // Query last week's water usage
  const { data: lastWeekData } = await supabase
    .from('sensor_readings')
    .select('recorded_at, flow_litres')
    .in('device_id', deviceIds)
    .gte('recorded_at', lastWeekStart.toISOString())
    .lt('recorded_at', weekStart.toISOString())
    .not('flow_litres', 'is', null);

  // Calculate totals
  const totalWaterUsed = thisWeekData?.reduce((sum, r) => sum + (r.flow_litres || 0), 0) || 0;
  const previousWeekTotal = lastWeekData?.reduce((sum, r) => sum + (r.flow_litres || 0), 0) || 0;

  // Daily breakdown
  const dailyMap = new Map<string, number>();
  thisWeekData?.forEach(r => {
    const date = new Date(r.recorded_at).toLocaleDateString('en-US', { timeZone: timezone });
    dailyMap.set(date, (dailyMap.get(date) || 0) + (r.flow_litres || 0));
  });

  const dailyBreakdown = Array.from(dailyMap.entries()).map(([date, total]) => ({
    date,
    total: Math.round(total * 100) / 100
  }));

  // Get alerts count
  const { count: alertsCount } = await supabase
    .from('system_alerts')
    .select('*', { count: 'exact', head: true })
    .eq('user_id', userId)
    .gte('created_at', weekStart.toISOString());

  return {
    totalWaterUsed: Math.round(totalWaterUsed * 100) / 100,
    previousWeekTotal: Math.round(previousWeekTotal * 100) / 100,
    dailyBreakdown,
    alertsCount: alertsCount || 0,
    devicesOnline,
    devicesTotal: devices.length
  };
}

async function sendWeeklyEmail(email: string, data: WeeklyData, timezone: string): Promise<void> {
  // Calculate percentage change
  let percentChange = 0;
  if (data.previousWeekTotal > 0) {
    percentChange = Math.round(((data.totalWaterUsed - data.previousWeekTotal) / data.previousWeekTotal) * 100);
  }

  const direction = percentChange > 0 ? '↑' : percentChange < 0 ? '↓' : '→';
  const changeText = data.previousWeekTotal > 0 
    ? `${direction} ${Math.abs(percentChange)}% vs last week`
    : '(no previous data for comparison)';

  // Build HTML email
  const html = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Weekly Farm Summary</title>
</head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px;">
    <div style="background: linear-gradient(135deg, #347433 0%, #059212 100%); padding: 30px; border-radius: 12px 12px 0 0;">
      <h1 style="color: white; margin: 0; font-size: 24px;">🌱 Your Weekly Farm Summary</h1>
      <p style="color: rgba(255,255,255,0.8); margin: 10px 0 0 0;">Smart Irrigation System</p>
    </div>
    
    <div style="background: #f9f9f9; padding: 30px; border-radius: 0 0 12px 12px;">
      <!-- Water Usage Section -->
      <div style="background: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1);">
        <h2 style="margin: 0 0 15px 0; color: #347433; font-size: 18px;">💧 Water Usage</h2>
        <div style="font-size: 32px; font-weight: bold; color: #2196F3;">
          ${data.totalWaterUsed.toFixed(1)} L
        </div>
        <p style="color: #666; margin: 5px 0 0 0; font-size: 14px;">
          ${changeText}
        </p>
        
        ${data.dailyBreakdown.length > 0 ? `
        <div style="margin-top: 15px;">
          <p style="font-size: 12px; color: #999; margin: 0 0 8px 0;">DAILY BREAKDOWN</p>
          <div style="display: flex; gap: 4px; height: 40px; align-items: flex-end;">
            ${data.dailyBreakdown.map(d => {
              const max = Math.max(...data.dailyBreakdown.map(x => x.total));
              const height = max > 0 ? (d.total / max) * 100 : 0;
              return `<div style="flex: 1; background: #2196F3; border-radius: 2px; height: ${height}%; min-height: 4px;" title="${d.date}: ${d.total.toFixed(1)}L"></div>`;
            }).join('')}
          </div>
        </div>
        ` : ''}
      </div>

      <!-- Alerts Section -->
      <div style="background: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1);">
        <h2 style="margin: 0 0 15px 0; color: #347433; font-size: 18px;">🔔 Alerts</h2>
        <div style="font-size: 24px; font-weight: bold; color: ${data.alertsCount > 0 ? '#FF9800' : '#4CAF50'};">
          ${data.alertsCount} ${data.alertsCount === 1 ? 'alert' : 'alerts'} this week
        </div>
      </div>

      <!-- Device Status Section -->
      <div style="background: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1);">
        <h2 style="margin: 0 0 15px 0; color: #347433; font-size: 18px;">📡 Device Status</h2>
        <div style="font-size: 24px; font-weight: bold; color: ${data.devicesOnline === data.devicesTotal ? '#4CAF50' : '#FF9800'};">
          ${data.devicesOnline} of ${data.devicesTotal} devices online
        </div>
        ${data.devicesOnline < data.devicesTotal ? `
        <p style="color: #FF9800; margin: 10px 0 0 0; font-size: 14px;">
          ⚠️ Some devices are offline. Check your dashboard for details.
        </p>
        ` : ''}
      </div>

      <!-- Footer -->
      <p style="text-align: center; color: #999; font-size: 12px; margin-top: 30px;">
        This is an automated weekly report from Smart Irrigation System.<br>
        <a href="#" style="color: #347433;">View Dashboard</a> | 
        <a href="#" style="color: #347433;">Unsubscribe</a>
      </p>
    </div>
  </body>
</html>
  `;

  // Send email using Supabase's internal email function or external service
  // This is a placeholder - in production, you would use Resend, SendGrid, or Supabase's SMTP
  console.log(`Sending weekly summary to ${email}:`, {
    totalWater: data.totalWaterUsed,
    alerts: data.alertsCount,
    devicesOnline: data.devicesOnline
  });
}
```

---

## purge-old-logs

Deletes pump logs older than 14 days to manage database storage.

### Purpose
- Automatic cleanup of old pump log entries
- Called daily via pg_cron schedule
- Reduces database bloat

### Environment Variables
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`

### Configuration
- Retention period: 14 days
- Table: `pump_logs`
- Column: `pump_on_at`

### Source Code

```typescript
// supabase/functions/purge-old-logs/index.ts
//
// Deletes all pump_logs rows where pump_on_at < now() - 14 days.
// Called daily by a pg_cron schedule (see migration file).
// Can also be invoked manually via an HTTP POST for testing.
//
// References:
//   Supabase Edge Functions: https://supabase.com/docs/guides/functions
//   supabase-js v2:          https://supabase.com/docs/reference/javascript

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Service-role key gives permission to delete rows regardless of RLS policies.
const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const RETENTION_DAYS = 14;

Deno.serve(async (_req: Request): Promise<Response> => {
  try {
    // Compute the cutoff timestamp
    const cutoff = new Date(
      Date.now() - RETENTION_DAYS * 24 * 60 * 60 * 1000,
    ).toISOString();

    // Delete rows older than cutoff and return a count of deleted rows
    const { error, count } = await supabase
      .from("pump_logs")
      .delete({ count: "exact" })
      .lt("pump_on_at", cutoff);

    if (error) {
      console.error("[purge-old-logs] Delete error:", error.message);
      return new Response(JSON.stringify({ error: error.message }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    const result = {
      deleted: count ?? 0,
      cutoff,
      retention_days: RETENTION_DAYS,
      timestamp: new Date().toISOString(),
    };

    console.log("[purge-old-logs]", JSON.stringify(result));

    return new Response(JSON.stringify(result), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("[purge-old-logs] Unexpected error:", err);
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
```

---

## send-alert-notification

Sends push notifications to users when new alerts are generated.

### Purpose
- Triggered by database webhook on `system_alerts` table insert
- Sends FCM push notifications to user devices
- Handles token refresh and stale token cleanup

### Environment Variables
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `FCM_SERVICE_ACCOUNT` (JSON service account key)

### Request Payload (from webhook)
```json
{
  "record": {
    "id": "number",
    "device_id": "uuid",
    "user_id": "uuid",
    "alert_type": "string",
    "message": "string"
  }
}
```

### Features
- JWT-based FCM authentication
- Android-specific notification settings
- Automatic removal of stale FCM tokens
- Maps alert types to readable titles

### Source Code

```typescript
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { encode as base64url } from "https://deno.land/std@0.168.0/encoding/base64url.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseAdmin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

type AlertRecord = {
  id?: number | string;
  device_id?: string;
  user_id?: string;
  alert_type?: string;
  message?: string;
};

function prettyAlertType(type: string): string {
  return type
    .split("_")
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

async function getFCMAccessToken(
  serviceAccount: Record<string, string>,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);

  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const enc = new TextEncoder();
  const headerB64 = base64url(enc.encode(JSON.stringify(header)).buffer);
  const payloadB64 = base64url(enc.encode(JSON.stringify(payload)).buffer);
  const signingInput = `${headerB64}.${payloadB64}`;

  const pemKey = serviceAccount.private_key;
  const pemContents = pemKey
    .replace("-----BEGIN RSA PRIVATE KEY-----", "")
    .replace("-----END RSA PRIVATE KEY-----", "")
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\n/g, "")
    .trim();

  const binaryKey = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0));

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    binaryKey,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    enc.encode(signingInput),
  );

  const jwt = `${signingInput}.${base64url(new Uint8Array(signature).buffer)}`;

  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });

  if (!tokenRes.ok) {
    const err = await tokenRes.text();
    throw new Error(`OAuth2 token exchange failed: ${err}`);
  }

  const tokenData = await tokenRes.json();
  return tokenData.access_token as string;
}

function buildNotification(record: AlertRecord): {
  title: string;
  body: string;
} {
  const type = prettyAlertType(record.alert_type ?? "Alert");
  const body = record.message?.trim() || "A new device alert was generated.";

  return {
    title: `RootSync Alert: ${type}`,
    body,
  };
}

async function resolveUserId(record: AlertRecord): Promise<string | null> {
  if (record.user_id) {
    return record.user_id;
  }

  if (!record.device_id) {
    return null;
  }

  const { data, error } = await supabaseAdmin
    .from("devices")
    .select("user_id")
    .eq("id", record.device_id)
    .maybeSingle();

  if (error) {
    throw new Error(`Failed to resolve user from device: ${error.message}`);
  }

  return (data?.user_id as string | null) ?? null;
}

serve(async (req: Request) => {
  try {
    const body = await req.json();
    console.log(
      "[send-alert-notification] Webhook payload:",
      JSON.stringify(body),
    );

    const record = body.record as AlertRecord | undefined;
    if (!record) {
      return new Response("No record in payload", { status: 400 });
    }

    const userId = await resolveUserId(record);
    if (!userId) {
      console.log("[send-alert-notification] No user resolved for alert");
      return new Response("No user resolved for alert", { status: 200 });
    }

    const { data: tokenRow, error: tokenError } = await supabaseAdmin
      .from("device_tokens")
      .select("fcm_token")
      .eq("user_id", userId)
      .maybeSingle();

    if (tokenError || !tokenRow?.fcm_token) {
      console.log(
        "[send-alert-notification] No FCM token found for user:",
        userId,
      );
      return new Response("No FCM token on file", { status: 200 });
    }

    const serviceAccountEnv = Deno.env.get("FCM_SERVICE_ACCOUNT");
    if (!serviceAccountEnv) {
      throw new Error("FCM_SERVICE_ACCOUNT env var is not set");
    }

    const serviceAccount = JSON.parse(serviceAccountEnv) as Record<
      string,
      string
    >;
    const accessToken = await getFCMAccessToken(serviceAccount);
    const { title, body: notifBody } = buildNotification(record);

    const fcmUrl = `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`;

    const fcmRes = await fetch(fcmUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify({
        message: {
          token: tokenRow.fcm_token,
          notification: {
            title,
            body: notifBody,
          },
          data: {
            alert_id: String(record.id ?? ""),
            alert_type: String(record.alert_type ?? ""),
            message: String(record.message ?? ""),
            screen: "alerts",
          },
          android: {
            priority: "high",
            notification: {
              channel_id: "rootsync_alerts",
              sound: "default",
              click_action: "FLUTTER_NOTIFICATION_CLICK",
              color: "#2E7D32",
              notification_priority: "PRIORITY_HIGH",
              visibility: "PUBLIC",
            },
          },
        },
      }),
    });

    const fcmResult = await fcmRes.json();
    console.log(
      "[send-alert-notification] FCM response:",
      JSON.stringify(fcmResult),
    );

    if (fcmResult.error) {
      const errStatus = fcmResult.error?.status;
      if (errStatus === "UNREGISTERED" || errStatus === "INVALID_ARGUMENT") {
        console.log("[send-alert-notification] Removing stale FCM token");
        await supabaseAdmin
          .from("device_tokens")
          .delete()
          .eq("fcm_token", tokenRow.fcm_token);
      }
    }

    return new Response(JSON.stringify(fcmResult), {
      headers: { "Content-Type": "application/json" },
      status: 200,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("[send-alert-notification] Edge function error:", message);
    return new Response(`Error: ${message}`, { status: 500 });
  }
});
```
