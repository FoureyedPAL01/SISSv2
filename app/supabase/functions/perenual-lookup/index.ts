// supabase/functions/perenual-lookup/index.ts
//
// Called by Flutter when a user taps "Fetch Plant Data" on a crop profile card.
// Looks up plant info from the Perenual API and caches the result in the
// crop_profiles table for 7 days to avoid burning through API quota.
//
// Expected request body: { "profile_id": 42, "plant_name": "Tomato" }
// Returns: { "ok": true, "data": { ... } }  or  { "ok": false, "error": "..." }

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// CORS headers — needed so the Flutter web build can call this function.
// For Android/Desktop this has no effect but including it does no harm.
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  // Preflight request — browsers send this before the real POST
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // -- Parse request body ------------------------------------------------
    const { profile_id, plant_name } = await req.json();

    if (!profile_id || !plant_name) {
      return new Response(
        JSON.stringify({
          ok: false,
          error: "profile_id and plant_name are required",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // -- Create a Supabase client with the service role key ----------------
    // Service role key is stored as a Supabase secret (never in Flutter).
    // It bypasses RLS so the function can update any crop_profiles row.
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // -- Check if cached data is still fresh (under 7 days) ----------------
    const { data: profile, error: fetchErr } = await supabase
      .from("crop_profiles")
      .select("perenual_cached_at, perenual_data")
      .eq("id", profile_id)
      .single();

    if (fetchErr) throw fetchErr;

    const SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000;
    const cachedAt = profile?.perenual_cached_at
      ? new Date(profile.perenual_cached_at).getTime()
      : 0;
    const isFresh = Date.now() - cachedAt < SEVEN_DAYS_MS;

    // If cache is still valid, return stored data without calling the API
    if (isFresh && profile?.perenual_data) {
      return new Response(
        JSON.stringify({
          ok: true,
          data: profile.perenual_data,
          source: "cache",
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // -- Cache is stale or missing — call Perenual API --------------------
    // PERENUAL_API_KEY is set via: supabase secrets set PERENUAL_API_KEY=your_key
    const apiKey = Deno.env.get("PERENUAL_API_KEY");
    if (!apiKey) throw new Error("PERENUAL_API_KEY secret not set");

    // Search by plant common name. Perenual returns a list; we take the first result.
    const perenualUrl = `https://perenual.com/api/species-list?key=${apiKey}&q=${encodeURIComponent(plant_name)}`;

    const perenualRes = await fetch(perenualUrl);
    if (!perenualRes.ok) {
      throw new Error(`Perenual API error: ${perenualRes.status}`);
    }

    const perenualJson = await perenualRes.json();
    const species = perenualJson?.data?.[0]; // first match

    if (!species) {
      return new Response(
        JSON.stringify({
          ok: false,
          error: `No results found for "${plant_name}"`,
        }),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // -- Extract the fields we care about ----------------------------------
    // Full Perenual species object contains many more fields; store a
    // trimmed version to keep the JSON column small.
    const plantData = {
      id: species.id,
      common_name: species.common_name,
      scientific_name: species.scientific_name?.[0] ?? null,
      watering: species.watering, // "Frequent" | "Average" | "Minimum" | "None"
      sunlight: species.sunlight, // array of strings
      cycle: species.cycle, // "Annual" | "Perennial" | "Biennial"
      image_url: species.default_image?.medium_url ?? null,
      description: species.description ?? null,
    };

    // -- Write result into crop_profiles row --------------------------------
    const { error: updateErr } = await supabase
      .from("crop_profiles")
      .update({
        perenual_species_id: species.id,
        perenual_data: plantData,
        perenual_cached_at: new Date().toISOString(),
      })
      .eq("id", profile_id);

    if (updateErr) throw updateErr;

    return new Response(
      JSON.stringify({ ok: true, data: plantData, source: "api" }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    return new Response(JSON.stringify({ ok: false, error: String(err) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
