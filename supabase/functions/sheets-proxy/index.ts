/// <reference lib="deno.ns" />
// La web (portada de PaginaLK) llama a /sheets-proxy. En Tierra Nativa el
// pipeline de Sheets ya existe como function `google-sheets` (que guarda el
// secreto del Apps Script). Este proxy reenvia el request tal cual, sin
// duplicar secretos.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const target = `${Deno.env.get("SUPABASE_URL")}/functions/v1/google-sheets`;
    const r = await fetch(target, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: req.headers.get("Authorization") || "",
        apikey: req.headers.get("apikey") || "",
      },
      body: await req.text(),
    });
    const body = await r.text();
    return new Response(body, {
      status: r.status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(
      JSON.stringify({ ok: false, error: String((e as Error)?.message || e) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
