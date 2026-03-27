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
