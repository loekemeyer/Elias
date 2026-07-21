/**
 * storage-size.js
 *
 * Requiere .env con SUPABASE_SERVICE_ROLE_KEY (ver .env.example).
 *
 * Calcula el peso total de todas las imágenes en el bucket products-images
 *
 * Uso: node storage-size.js
 */

const { createAdminClient } = require("./supabase-admin-client");

const BUCKET = "products-images";

const supabase = createAdminClient();

function formatBytes(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}

async function main() {
  const { data: rootItems, error } = await supabase.storage
    .from(BUCKET)
    .list("", { limit: 1000 });
  if (error) throw new Error(error.message);

  const folders = (rootItems || []).filter((i) => i.id === null);
  const rootFiles = (rootItems || []).filter((i) => i.id !== null);

  let totalSize = 0;
  let totalFiles = 0;
  let folderStats = [];

  // Archivos en raíz
  let rootSize = 0;
  let rootCount = 0;
  for (const f of rootFiles) {
    const s = f.metadata?.size ?? 0;
    rootSize += s;
    rootCount++;
  }
  if (rootCount) folderStats.push({ name: "(raíz)", count: rootCount, size: rootSize });
  totalSize += rootSize;
  totalFiles += rootCount;

  // Carpetas
  for (const folder of folders) {
    const { data: files, error: fErr } = await supabase.storage
      .from(BUCKET)
      .list(folder.name, { limit: 1000 });
    if (fErr) continue;

    let folderSize = 0;
    let folderCount = 0;
    for (const f of (files || []).filter((i) => i.id !== null)) {
      const s = f.metadata?.size ?? 0;
      folderSize += s;
      folderCount++;
    }
    if (folderCount) folderStats.push({ name: folder.name, count: folderCount, size: folderSize });
    totalSize += folderSize;
    totalFiles += folderCount;
  }

  // Top 10 carpetas más pesadas
  folderStats.sort((a, b) => b.size - a.size);
  console.log("📊 Top 10 carpetas más pesadas:\n");
  folderStats.slice(0, 10).forEach((f, i) => {
    console.log(`  ${i + 1}. ${f.name}  →  ${f.count} archivos  →  ${formatBytes(f.size)}`);
  });

  console.log("\n─────────────────────────────────");
  console.log(`  Carpetas totales : ${folders.length}`);
  console.log(`  Archivos totales : ${totalFiles}`);
  console.log(`  Peso total       : ${formatBytes(totalSize)}`);
}

main().catch((err) => {
  console.error("❌ Error:", err.message);
  process.exit(1);
});
