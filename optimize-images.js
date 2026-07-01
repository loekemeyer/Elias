/**
 * optimize-images.js
 *
 * Descarga todas las imágenes de Supabase Storage, las convierte a WebP
 * con calidad 80 y las re-sube. Actualiza la columna `images` en products
 * si el path cambió (ej: 1.jpg → 1.webp).
 *
 * Uso:
 *   node optimize-images.js          ← dry-run (solo muestra qué haría)
 *   node optimize-images.js --run    ← ejecuta los cambios reales
 *
 * Requiere:
 *   npm install @supabase/supabase-js sharp
 */

const { createClient } = require("@supabase/supabase-js");
const sharp = require("sharp");

const SUPABASE_URL = "https://zjvpzqhbekxnwxdczpof.supabase.co";
const SUPABASE_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpqdnB6cWhiZWt4bnd4ZGN6cG9mIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NDAyNTI5OSwiZXhwIjoyMDg5NjAxMjk5fQ.kPO2Ku3lAI-c5wC7STD-AIRcI6ww9PKG60Vsn_UJIu4";
const BUCKET = "products-images";
const WEBP_QUALITY = 80;

const DRY_RUN = !process.argv.includes("--run");

const supabase = createClient(SUPABASE_URL, SUPABASE_KEY);

const IMAGE_EXTS = new Set([".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".tiff"]);

function getExt(filename) {
  const dot = filename.lastIndexOf(".");
  return dot === -1 ? "" : filename.substring(dot).toLowerCase();
}

function stripExt(filename) {
  const dot = filename.lastIndexOf(".");
  return dot === -1 ? filename : filename.substring(0, dot);
}

function formatBytes(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}

async function listFolders() {
  const { data, error } = await supabase.storage
    .from(BUCKET)
    .list("", { limit: 1000 });
  if (error) throw new Error("Error listando carpetas: " + error.message);
  return (data || []).filter((i) => i.id === null).map((i) => i.name);
}

async function listFilesInFolder(folder) {
  const { data, error } = await supabase.storage
    .from(BUCKET)
    .list(folder, { limit: 1000 });
  if (error) throw new Error(`Error listando ${folder}: ` + error.message);
  return (data || [])
    .filter((i) => i.id !== null && IMAGE_EXTS.has(getExt(i.name)))
    .map((i) => ({
      name: i.name,
      path: `${folder}/${i.name}`,
      size: i.metadata?.size ?? 0,
    }));
}

async function downloadFile(path) {
  const { data, error } = await supabase.storage.from(BUCKET).download(path);
  if (error) throw new Error(`Error descargando ${path}: ` + error.message);
  return Buffer.from(await data.arrayBuffer());
}

async function uploadFile(path, buffer, upsert = true) {
  const { error } = await supabase.storage
    .from(BUCKET)
    .upload(path, buffer, { contentType: "image/webp", upsert });
  if (error) throw new Error(`Error subiendo ${path}: ` + error.message);
}

async function deleteFile(path) {
  const { error } = await supabase.storage.from(BUCKET).remove([path]);
  if (error) throw new Error(`Error eliminando ${path}: ` + error.message);
}

async function main() {
  console.log(DRY_RUN
    ? "🔍 DRY RUN — no se modifica nada\n"
    : "🚀 EJECUTANDO optimización real\n"
  );

  const folders = await listFolders();
  console.log(`Carpetas encontradas: ${folders.length}\n`);

  let totalOriginal = 0;
  let totalCompressed = 0;
  let filesProcessed = 0;
  let filesSkipped = 0;

  // pathMap: oldPath → newPath (solo si cambia la extensión)
  const pathMap = new Map();

  for (const folder of folders) {
    const files = await listFilesInFolder(folder);
    if (!files.length) continue;

    console.log(`📁 ${folder} (${files.length} imagen${files.length !== 1 ? "es" : ""})`);

    for (const file of files) {
      const ext = getExt(file.name);
      const base = stripExt(file.name);
      const newName = `${base}.webp`;
      const newPath = `${folder}/${newName}`;
      const extChanged = ext !== ".webp";

      if (DRY_RUN) {
        const tag = extChanged ? `${file.name} → ${newName}` : `${file.name} (recomprimir)`;
        console.log(`   ${tag}`);
        if (extChanged) pathMap.set(file.path, newPath);
        filesProcessed++;
        continue;
      }

      try {
        // Descargar
        const original = await downloadFile(file.path);
        const originalSize = original.length;

        // Comprimir a WebP
        const compressed = await sharp(original)
          .webp({ quality: WEBP_QUALITY })
          .toBuffer();
        const compressedSize = compressed.length;

        // Subir como .webp
        await uploadFile(newPath, compressed);

        // Si cambió la extensión, borrar el original
        if (extChanged) {
          await deleteFile(file.path);
          pathMap.set(file.path, newPath);
        }

        totalOriginal += originalSize;
        totalCompressed += compressedSize;
        filesProcessed++;

        const saved = originalSize - compressedSize;
        const pct = originalSize > 0 ? Math.round((saved / originalSize) * 100) : 0;
        const tag = extChanged ? `${file.name} → ${newName}` : file.name;
        console.log(`   ✓ ${tag}  ${formatBytes(originalSize)} → ${formatBytes(compressedSize)}  (-${pct}%)`);
      } catch (err) {
        console.error(`   ✗ ${file.name}: ${err.message}`);
        filesSkipped++;
      }
    }
  }

  // Actualizar columna images en products si hubo cambios de extensión
  if (!DRY_RUN && pathMap.size > 0) {
    console.log(`\n📝 Actualizando columna images en products...`);

    const { data: prods, error: prodErr } = await supabase
      .from("products")
      .select("id, cod, images")
      .not("images", "is", null);

    if (prodErr) throw new Error("Error leyendo products: " + prodErr.message);

    let updatedProds = 0;
    for (const prod of prods || []) {
      if (!Array.isArray(prod.images) || !prod.images.length) continue;

      const updated = prod.images.map((img) => {
        // El path en DB puede o no tener prefijo del bucket, normalizar
        const clean = img.replace(/^\/+/, "");
        return pathMap.get(clean) ?? pathMap.get(img) ?? img;
      });

      const changed = updated.some((v, i) => v !== prod.images[i]);
      if (!changed) continue;

      const { error: updErr } = await supabase
        .from("products")
        .update({ images: updated })
        .eq("id", prod.id);

      if (updErr) {
        console.error(`   ✗ Producto ${prod.cod}: ${updErr.message}`);
      } else {
        console.log(`   ✓ Producto ${prod.cod}`);
        updatedProds++;
      }
    }
    console.log(`   ${updatedProds} productos actualizados.`);
  }

  // Resumen
  console.log("\n─────────────────────────────────");
  if (DRY_RUN) {
    console.log(`✅ Dry run completo.`);
    console.log(`   ${filesProcessed} imágenes serían procesadas.`);
    if (pathMap.size > 0)
      console.log(`   ${pathMap.size} paths cambiarían de extensión (columna images se actualizaría).`);
    console.log("\nEjecutá con --run para aplicar los cambios.");
  } else {
    const saved = totalOriginal - totalCompressed;
    const pct = totalOriginal > 0 ? Math.round((saved / totalOriginal) * 100) : 0;
    console.log(`✅ Optimización completa.`);
    console.log(`   Archivos procesados : ${filesProcessed}`);
    console.log(`   Archivos con error  : ${filesSkipped}`);
    console.log(`   Peso original       : ${formatBytes(totalOriginal)}`);
    console.log(`   Peso final          : ${formatBytes(totalCompressed)}`);
    console.log(`   Ahorro total        : ${formatBytes(saved)} (-${pct}%)`);
  }
}

main().catch((err) => {
  console.error("\n❌ Error fatal:", err.message);
  process.exit(1);
});
