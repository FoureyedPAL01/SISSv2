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
