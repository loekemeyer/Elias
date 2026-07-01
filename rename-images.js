/**
 * rename-images.js
 *
 * Renombra todas las imágenes numeradas en Supabase Storage +1
 * (1.jpg → 2.jpg, 2.jpg → 3.jpg, etc.)
 * y actualiza la columna `images` en la tabla products.
 *
 * Uso:
 *   node rename-images.js          ← dry-run (solo muestra qué haría)
 *   node rename-images.js --run    ← ejecuta los cambios reales
 */

const { createClient } = require("@supabase/supabase-js");

const SUPABASE_URL = "https://zjvpzqhbekxnwxdczpof.supabase.co";
const SUPABASE_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpqdnB6cWhiZWt4bnd4ZGN6cG9mIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NDAyNTI5OSwiZXhwIjoyMDg5NjAxMjk5fQ.kPO2Ku3lAI-c5wC7STD-AIRcI6ww9PKG60Vsn_UJIu4";
const BUCKET = "products-images";

const DRY_RUN = !process.argv.includes("--run");

const supabase = createClient(SUPABASE_URL, SUPABASE_KEY);

function getBase(filename) {
  const dot = filename.lastIndexOf(".");
  return dot === -1 ? filename : filename.substring(0, dot);
}

function getExt(filename) {
  const dot = filename.lastIndexOf(".");
  return dot === -1 ? "" : filename.substring(dot);
}

async function listFolders() {
  const { data, error } = await supabase.storage
    .from(BUCKET)
    .list("", { limit: 1000 });
  if (error) throw new Error("Error listando carpetas: " + error.message);
  // Las carpetas tienen id === null
  return (data || []).filter((item) => item.id === null).map((item) => item.name);
}

async function listFilesInFolder(folder) {
  const { data, error } = await supabase.storage
    .from(BUCKET)
    .list(folder, { limit: 1000 });
  if (error) throw new Error(`Error listando ${folder}: ` + error.message);
  return (data || [])
    .filter((item) => item.id !== null)
    .map((item) => ({ name: item.name, path: `${folder}/${item.name}` }));
}

async function main() {
  console.log(DRY_RUN ? "🔍 DRY RUN — no se ejecuta nada\n" : "🚀 EJECUTANDO cambios reales\n");

  // 1. Listar todas las carpetas (códigos de producto)
  const folders = await listFolders();
  console.log(`Carpetas encontradas: ${folders.length}\n`);

  const renames = []; // [{ oldPath, newPath }]

  // 2. Por cada carpeta, detectar archivos numerados y ordenar descendente
  for (const folder of folders) {
    const files = await listFilesInFolder(folder);
    const numbered = files.filter((f) => /^\d+$/.test(getBase(f.name)));
    if (!numbered.length) continue;

    // Orden descendente para evitar pisar archivos (3→4, 2→3, 1→2)
    numbered.sort(
      (a, b) => parseInt(getBase(b.name)) - parseInt(getBase(a.name))
    );

    for (const file of numbered) {
      const num = parseInt(getBase(file.name));
      const ext = getExt(file.name);
      const newPath = `${folder}/${num + 1}${ext}`;
      renames.push({ oldPath: file.path, newPath });
      console.log(`  ${file.path}  →  ${newPath}`);
    }
  }

  console.log(`\nTotal de archivos a renombrar: ${renames.length}`);

  if (DRY_RUN) {
    console.log("\n✅ Dry run completo. Ejecutá con --run para aplicar los cambios.");
    return;
  }

  if (renames.length === 0) {
    console.log("Nada para renombrar.");
    return;
  }

  // 3. Ejecutar renombrados en Supabase Storage (copy + delete)
  console.log("\n📦 Renombrando archivos en Storage...");
  const renameMap = new Map();

  for (const { oldPath, newPath } of renames) {
    const { error: copyErr } = await supabase.storage
      .from(BUCKET)
      .copy(oldPath, newPath);
    if (copyErr) {
      console.error(`  ✗ ERROR copiando ${oldPath}: ${copyErr.message}`);
      continue;
    }

    const { error: delErr } = await supabase.storage
      .from(BUCKET)
      .remove([oldPath]);
    if (delErr) {
      console.error(`  ✗ ERROR eliminando ${oldPath}: ${delErr.message}`);
      continue;
    }

    renameMap.set(oldPath, newPath);
    console.log(`  ✓ ${oldPath} → ${newPath}`);
  }

  // 4. Actualizar columna images en la tabla products
  console.log("\n📝 Actualizando columna images en products...");

  const { data: prods, error: prodErr } = await supabase
    .from("products")
    .select("id, cod, images")
    .not("images", "is", null);

  if (prodErr) throw new Error("Error leyendo products: " + prodErr.message);

  let updatedCount = 0;

  for (const prod of prods || []) {
    if (!Array.isArray(prod.images) || !prod.images.length) continue;

    const updated = prod.images.map((img) => renameMap.get(img) ?? img);
    const changed = updated.some((v, i) => v !== prod.images[i]);
    if (!changed) continue;

    const { error: updErr } = await supabase
      .from("products")
      .update({ images: updated })
      .eq("id", prod.id);

    if (updErr) {
      console.error(`  ✗ ERROR actualizando ${prod.cod}: ${updErr.message}`);
    } else {
      console.log(`  ✓ Producto ${prod.cod} actualizado`);
      updatedCount++;
    }
  }

  console.log(`\n✅ Listo. ${renameMap.size} archivos renombrados, ${updatedCount} productos actualizados.`);
}

main().catch((err) => {
  console.error("\n❌ Error fatal:", err.message);
  process.exit(1);
});
