/// <reference lib="deno.ns" />
// Registra el alta de una nueva direccion de entrega en address_notifications
// para que ventas la revise desde el panel. Usa el JWT del usuario (policy
// address_notifications_insert_own), sin depender de claves privilegiadas.

import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function bad(status: number, error: string) {
  return new Response(JSON.stringify({ ok: false, error }), {
    status, headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    const apikey = req.headers.get("apikey") || "";
    if (!jwt || !apikey) return bad(401, "Missing token");

    const asUser = createClient(Deno.env.get("SUPABASE_URL")!, apikey, {
      global: { headers: { Authorization: `Bearer ${jwt}` } },
    });
    const { data: userData, error: userErr } = await asUser.auth.getUser();
    if (userErr || !userData?.user) return bad(401, "Invalid token");

    const body = await req.json().catch(() => ({}));
    const { error } = await asUser.from("address_notifications").insert({
      customer_id: body?.customer_id || null,
      auth_user_id: userData.user.id,
      slot: body?.slot != null ? String(body.slot) : null,
    });
    if (error) throw error;

    return new Response(JSON.stringify({ ok: true }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return bad(500, String((e as Error)?.message || e));
  }
});
