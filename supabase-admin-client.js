/**
 * supabase-admin-client.js
 *
 * Cliente Supabase con service_role para los scripts de mantenimiento de storage.
 * La key NO vive en el codigo: se lee de la variable de entorno
 * SUPABASE_SERVICE_ROLE_KEY (ver .env.example).
 *
 * Uso:
 *   const { createAdminClient } = require("./supabase-admin-client");
 *   const supabase = createAdminClient();
 */

require("dotenv").config();

const { createClient } = require("@supabase/supabase-js");

const SUPABASE_URL =
  process.env.SUPABASE_URL || "https://zjvpzqhbekxnwxdczpof.supabase.co";

function createAdminClient() {
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) {
    console.error(
      "\n[ERROR] Falta la variable de entorno SUPABASE_SERVICE_ROLE_KEY.\n" +
        "  1. Copiar .env.example a .env\n" +
        "  2. Pegar la service_role key del dashboard de Supabase\n" +
        "     (Project Settings > API > service_role)\n" +
        "  El archivo .env esta en .gitignore y NO se versiona.\n"
    );
    process.exit(1);
  }
  return createClient(SUPABASE_URL, key);
}

module.exports = { createAdminClient, SUPABASE_URL };
