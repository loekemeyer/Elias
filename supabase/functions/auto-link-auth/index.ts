// Supabase Edge Function: auto-link-auth
// Vincula automáticamente el auth_user_id de un usuario autenticado con su fila
// en customers, buscando por CUIT (derivado del email de auth).
//
// Se llama desde script.js cuando refreshAuthState() no encuentra la fila del
// cliente por auth_user_id. El flujo es:
//   1. El front intenta .eq("auth_user_id", uid) → null (el link falta).
//   2. El front llama a esta función con el JWT.
//   3. Esta función busca por CUIT con service role (saltea RLS), linkea el
//      auth_user_id si falta, y devuelve la fila.
//   4. En futuros logins el .eq("auth_user_id") ya funciona directo.
//
// POST /functions/v1/auto-link-auth
// Headers: Authorization: Bearer <jwt>, apikey: <anon_key>
// Body: (vacío o {})
// Respuesta OK: { customer: { id, business_name, ... } }
// Respuesta error: { error: "..." }

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY =
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

// Columnas que devuelve refreshAuthState() en el front.
const CUSTOMER_COLS =
  "id,business_name,dto_vol,cod_cliente,cuit,direccion_fiscal,localidad,vend,mail,debt,payment_term,credit_limit";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      return jsonResponse({ error: "missing_auth" }, 401);
    }
    const jwt = authHeader.slice(7);

    if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
      return jsonResponse({ error: "server_misconfigured" }, 500);
    }

    // Cliente con service role: saltea RLS.
    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    // Verificar el JWT y obtener el usuario.
    const userRes = await admin.auth.getUser(jwt);
    if (userRes.error || !userRes.data?.user) {
      return jsonResponse({ error: "invalid_auth" }, 401);
    }
    const user = userRes.data.user;
    const email = (user.email ?? "").toLowerCase();

    // Extraer dígitos del CUIT del email (formato: <digits>@cuit.tierranativa).
    const match = email.match(/^(\d+)@cuit\.tierranativa$/);
    if (!match) {
      return jsonResponse({ error: "email_not_cuit" }, 400);
    }
    const cuitDigits = match[1];

    // Primero intentar por auth_user_id (si ya está linkeado, devolver directo).
    const byAuth = await admin
      .from("customers")
      .select(CUSTOMER_COLS)
      .eq("auth_user_id", user.id)
      .maybeSingle();

    if (byAuth.data) {
      return jsonResponse({ customer: byAuth.data });
    }

    // Buscar por CUIT (los CUITs se guardan como dígitos sin guiones).
    const byCuit = await admin
      .from("customers")
      .select(CUSTOMER_COLS + ",auth_user_id")
      .eq("cuit", cuitDigits)
      .maybeSingle();

    if (!byCuit.data) {
      return jsonResponse({ error: "customer_not_found" }, 404);
    }

    // Si el auth_user_id falta o apunta a otro usuario, linkearlo.
    if (!byCuit.data.auth_user_id) {
      const upd = await admin
        .from("customers")
        .update({ auth_user_id: user.id })
        .eq("id", byCuit.data.id);

      if (upd.error) {
        // Loguear el error pero devolver la fila igual — el link se arregla
        // la próxima vez o con "Reparar Auth".
        console.error("auto-link-auth update error:", upd.error.message);
      }
    }

    // Devolver la fila sin el auth_user_id (no es dato del front).
    const { auth_user_id: _drop, ...customer } = byCuit.data;
    return jsonResponse({ customer });
  } catch (e) {
    console.error("auto-link-auth exception:", e);
    return jsonResponse({ error: "exception", detail: String(e) }, 500);
  }
});
