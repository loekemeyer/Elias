/**
 * compress-75kb.js
 *
 * Comprime todas las imágenes que pesen más de 75 KB hasta que estén
 * por debajo de ese tope. Baja la calidad progresivamente y como último
 * recurso reduce las dimensiones, manteniendo la mejor calidad posible.
 *
 * Uso:
 *   node compress-75kb.js          ← dry-run (solo muestra qué haría)
 *   node compress-75kb.js --run    ← ejecuta los cambios reales
 */

const { createClient } = require("@supabase/supabase-js");
const sharp = require("sharp");

const SUPABASE_URL = "https://zjvpzqhbekxnwxdczpof.supabase.co";
const SUPABASE_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpqdnB6cWhiZWt4bnd4ZGN6cG9mIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NDAyNTI5OSwiZXhwIjoyMDg5NjAxMjk5fQ.kPO2Ku3lAI-c5wC7STD-AIRcI6ww9PKG60Vsn_UJIu4";
const BUCKET = "products-images";
const MAX_SIZE = 75 * 1024; // 75 KB en bytes

const DRY_RUN = !process.argv.includes("--run");
const supabase = createClient(SUPABASE_URL, SUPABASE_KEY);

function formatBytes(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}

async function compressToTarget(buffer) {
  // Paso 1: intentar bajando calidad de 90 a 50
  for (let q = 90; q >= 50; q -= 5) {
    const result = await sharp(buffer).webp({ quality: q }).toBuffer();
    if (result.length <= MAX_SIZE) return { buffer: result, quality: q, resized: false };
  }

  // Paso 2: calidad 50 + reducir dimensiones progresivamente
  const meta = await sharp(buffer).metadata();
  let width = meta.width || 1200;

  const scales = [0.85, 0.7, 0.6, 0.5, 0.4];
  for (const scale of scales) {
    const newW = Math.round(width * scale);
    const result = await sharp(buffer)
      .resize(newW, null, { withoutEnlargement: true })
      .webp({ quality: 50 })
      .toBuffer();
    if (result.length <= MAX_SIZE) return { buffer: result, quality: 50, resized: true, newWidth: newW };
  }

  // Último recurso: el más pequeño que pudimos lograr
  const smallest = await sharp(buffer)
    .resize(Math.round(width * 0.4), null, { withoutEnlargement: true })
    .webp({ quality: 40 })
    .toBuffer();
  return { buffer: smallest, quality: 40, resized: true, newWidth: Math.round(width * 0.4) };
}

async function listFolders() {
  const { data, error } = await supabase.storage.from(BUCKET).list("", { limit: 1000 });
  if (error) throw new Error(error.message);
  return data || [];
}

async function listFilesInFolder(folder) {
  const { data, error } = await supabase.storage.from(BUCKET).list(folder, { limit: 1000 });
  if (error) throw new Error(error.message);
  return (data || []).filter((i) => i.id !== null);
}

async function main() {
  console.log(DRY_RUN
    ? "🔍 DRY RUN — no se modifica nada\n"
    : "🚀 EJECUTANDO compresión real\n"
  );

  const rootItems = await listFolders();
  const folders = rootItems.filter((i) => i.id === null);
  const rootFiles = rootItems.filter((i) => i.id !== null);

  // Recolectar todos los archivos > 75 KB
  const oversized = [];

  for (const f of rootFiles) {
    const size = f.metadata?.size ?? 0;
    if (size > MAX_SIZE) oversized.push({ path: f.name, size });
  }

  for (const folder of folders) {
    const files = await listFilesInFolder(folder.name);
    for (const f of files) {
      const size = f.metadata?.size ?? 0;
      if (size > MAX_SIZE) oversized.push({ path: `${folder.name}/${f.name}`, size });
    }
  }

  if (oversized.length === 0) {
    console.log("✅ No hay imágenes mayores a 75 KB. Todo OK.");
    return;
  }

  let totalOriginal = 0;
  let totalFinal = 0;
  let processed = 0;
  let errors = 0;

  console.log(`⚠️  Imágenes > 75 KB: ${oversized.length}\n`);

  for (const file of oversized) {
    totalOriginal += file.size;

    if (DRY_RUN) {
      console.log(`  ${file.path}  (${formatBytes(file.size)})`);
      processed++;
      continue;
    }

    try {
      // Descargar
      const { data, error: dlErr } = await supabase.storage.from(BUCKET).download(file.path);
      if (dlErr) throw new Error(dlErr.message);
      const original = Buffer.from(await data.arrayBuffer());

      // Comprimir
      const result = await compressToTarget(original);

      // Subir
      const { error: upErr } = await supabase.storage
        .from(BUCKET)
        .upload(file.path, result.buffer, { contentType: "image/webp", upsert: true });
      if (upErr) throw new Error(upErr.message);

      totalFinal += result.buffer.length;
      processed++;

      const saved = file.size - result.buffer.length;
      const pct = Math.round((saved / file.size) * 100);
      const note = result.resized ? ` (q${result.quality}, ${result.newWidth}px)` : ` (q${result.quality})`;
      console.log(`  ✓ ${file.path}  ${formatBytes(file.size)} → ${formatBytes(result.buffer.length)}  -${pct}%${note}`);
    } catch (err) {
      console.error(`  ✗ ${file.path}: ${err.message}`);
      errors++;
    }
  }

  console.log("\n─────────────────────────────────");
  if (DRY_RUN) {
    console.log(`✅ Dry run completo.`);
    console.log(`   ${processed} imágenes serían comprimidas.`);
    console.log(`   Peso actual: ${formatBytes(totalOriginal)}`);
    console.log(`\nEjecutá con --run para aplicar.`);
  } else {
    const saved = totalOriginal - totalFinal;
    const pct = totalOriginal > 0 ? Math.round((saved / totalOriginal) * 100) : 0;
    console.log(`✅ Compresión completa.`);
    console.log(`   Procesados  : ${processed}`);
    console.log(`   Errores     : ${errors}`);
    console.log(`   Peso antes  : ${formatBytes(totalOriginal)}`);
    console.log(`   Peso después: ${formatBytes(totalFinal)}`);
    console.log(`   Ahorro      : ${formatBytes(saved)} (-${pct}%)`);
  }
}

main().catch((err) => {
  console.error("❌ Error:", err.message);
  process.exit(1);
});
