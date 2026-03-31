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
    title: `SISS Alert: ${type}`,
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
    // 1. Get raw text to prevent crashing on empty/bad bodies
    const rawBody = await req.text();
    if (!rawBody) throw new Error("Empty request body");

    const payload = JSON.parse(rawBody);
    console.log("[send-alert-notification] Payload received:", rawBody);

    // 2. Supabase webhooks wrap the data in a 'record' field
    // We check both payload.record (webhook) and payload (direct call)
    const record = payload.record || payload;

    const { device_id, message, alert_type } = record;
    console.log(`[send-alert-notification] Processing alert for device: ${device_id}, type: ${alert_type}`);

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
              channel_id: "sissv2_alerts",
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
