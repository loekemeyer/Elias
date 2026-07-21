/**
 * download-all-images.js
 *
 * Requiere .env con SUPABASE_SERVICE_ROLE_KEY (ver .env.example).
 *
 * Descarga TODAS las imágenes del bucket products-images
 * manteniendo la estructura de carpetas.
 *
 * Uso: node download-all-images.js
 *
 * Se guardan en: ./backup-images/
 */

const { createAdminClient } = require("./supabase-admin-client");
const fs = require("fs");
const path = require("path");

const BUCKET = "products-images";
const OUTPUT_DIR = path.join(__dirname, "backup-images");

const supabase = createAdminClient();

function formatBytes(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}

async function scanFolder(prefix) {
  const { data, error } = await supabase.storage
    .from(BUCKET)
    .list(prefix, { limit: 1000 });
  if (error || !data) return [];

  let files = [];
  for (const item of data) {
    const fullPath = prefix ? `${prefix}/${item.name}` : item.name;
    if (item.id === null) {
      const nested = await scanFolder(fullPath);
      files = files.concat(nested);
    } else {
      files.push(fullPath);
    }
  }
  return files;
}

async function main() {
  console.log("📂 Escaneando bucket...\n");
  const files = await scanFolder("");
  console.log(`   ${files.length} archivos encontrados.\n`);

  if (!files.length) return;

  if (!fs.existsSync(OUTPUT_DIR)) fs.mkdirSync(OUTPUT_DIR, { recursive: true });

  let downloaded = 0;
  let errors = 0;
  let totalSize = 0;

  for (const filePath of files) {
    const localPath = path.join(OUTPUT_DIR, ...filePath.split("/"));
    const localDir = path.dirname(localPath);
    if (!fs.existsSync(localDir)) fs.mkdirSync(localDir, { recursive: true });

    try {
      const { data, error } = await supabase.storage.from(BUCKET).download(filePath);
      if (error) throw new Error(error.message);

      const buffer = Buffer.from(await data.arrayBuffer());
      fs.writeFileSync(localPath, buffer);
      totalSize += buffer.length;
      downloaded++;

      process.stdout.write(`\r   Descargado: ${downloaded}/${files.length}`);
    } catch (err) {
      console.error(`\n   ✗ ${filePath}: ${err.message}`);
      errors++;
    }
  }

  console.log(`\n\n─────────────────────────────────`);
  console.log(`✅ Backup completo.`);
  console.log(`   Descargados : ${downloaded}`);
  console.log(`   Errores     : ${errors}`);
  console.log(`   Peso total  : ${formatBytes(totalSize)}`);
  console.log(`   Guardado en : ${OUTPUT_DIR}`);
}

main().catch((err) => {
  console.error("❌ Error:", err.message);
  process.exit(1);
});
