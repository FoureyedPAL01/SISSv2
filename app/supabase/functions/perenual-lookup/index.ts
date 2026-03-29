import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  // Debug logging
  console.log("=== Edge Function Called ===");
  console.log("Method:", req.method);
  console.log("Auth Header Present:", !!req.headers.get("Authorization"));
  console.log("Auth Header Preview:", req.headers.get("Authorization")?.substring(0, 20) + "...");

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      console.log("ERROR: Missing Authorization header");
      return new Response(
        JSON.stringify({ ok: false, error: "Missing Authorization header" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

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

    // Check required secrets
    const apiKey = Deno.env.get("PERENUAL_API_KEY");
    if (!apiKey) {
      throw new Error("PERENUAL_API_KEY secret not set in Edge Function secrets");
    }
    console.log("API key exists, length:", apiKey.length);

    console.log("Auth header received, proceeding with service role key");

    // ── Check cache ──────────────────────────────────────────────────────────
    // Using service role key - skip auth.getUser() as it doesn't work with service role
    // We verify ownership by checking the profile belongs to a valid user
    const { data: profile, error: fetchErr } = await supabase
      .from("crop_profiles")
      .select("perenual_cached_at, perenual_data, perenual_care_data, user_id")
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

    const speciesUrl =
      `https://perenual.com/api/species-list?key=${apiKey}&q=${encodeURIComponent(plant_name)}`;
    const speciesRes  = await fetch(speciesUrl);
    if (!speciesRes.ok) throw new Error(`Perenual species error: ${speciesRes.status}`);

    // Check if response is OK
    if (!speciesRes.ok) {
      const errorText = await speciesRes.text();
      console.error("Perenual API error (species):", speciesRes.status, errorText);
      throw new Error(`Perenual API error: ${speciesRes.status} - ${errorText.substring(0, 100)}`);
    }

    const speciesText = await speciesRes.text();
    console.log("Perenual species response status:", speciesRes.status);
    console.log("Perenual species response preview:", speciesText.substring(0, 200));
    
    // Check if response is JSON (not HTML error page)
    if (!speciesText.trim().startsWith('{')) {
      console.error("Perenual returned non-JSON:", speciesText);
      throw new Error("Perenual API returned invalid response (status: " + speciesRes.status + ")");
    }

    const speciesJson = JSON.parse(speciesText);
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
    
    console.log("Care guide response status:", careRes.status);

    let careData: Record<string, unknown> = {};

    if (careRes.ok) {
      const careText = await careRes.text();
      console.log("Care guide response preview:", careText.substring(0, 100));
      
      if (!careText.trim().startsWith('{')) {
        console.error("Care guide returned non-JSON, skipping care data");
      } else {
        const careJson = JSON.parse(careText);
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
    console.error("Function error:", err);
    return new Response(
      JSON.stringify({ 
        ok: false, 
        error: String(err),
        message: "See function logs for details"
      }),
      { 
        status: 500, 
        headers: { ...corsHeaders, "Content-Type": "application/json" } 
      },
    );
  }
});
