/// <reference lib="deno.ns" />
// Sube el comprobante PDF de un pedido al bucket privado pedidos-pdf.
// Autorizacion 100% via JWT del usuario: la RPC vendor_get_order_full valida
// el acceso al pedido y las policies de storage validan la escritura.

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

    const body = await req.json().catch(() => null);
    const orderId = Number(body?.order_id);
    const pdfBase64 = String(body?.pdf_base64 || "");
    if (!orderId || !pdfBase64) return bad(400, "order_id y pdf_base64 requeridos");
    if (pdfBase64.length > 15_000_000) return bad(413, "PDF demasiado grande");

    const asUser = createClient(Deno.env.get("SUPABASE_URL")!, apikey, {
      global: { headers: { Authorization: `Bearer ${jwt}` } },
    });
    const { data: orderFull, error: rpcErr } = await asUser.rpc(
      "vendor_get_order_full",
      { p_order_id: orderId },
    );
    if (rpcErr) return bad(500, `auth check: ${rpcErr.message}`);
    if (!orderFull) return bad(403, "No autorizado para este pedido");

    const bin = Uint8Array.from(atob(pdfBase64), (c) => c.charCodeAt(0));
    const path = `pedido-${orderId}.pdf`;
    const { error: upErr } = await asUser.storage
      .from("pedidos-pdf")
      .upload(path, bin, { contentType: "application/pdf", upsert: true });
    if (upErr) return bad(500, `upload: ${upErr.message}`);

    return new Response(JSON.stringify({ ok: true, path }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return bad(500, String((e as Error)?.message || e));
  }
});
