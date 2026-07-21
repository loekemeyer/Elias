/**
 * check-non-webp.js
 *
 * Requiere .env con SUPABASE_SERVICE_ROLE_KEY (ver .env.example).
 *
 * Lista todos los archivos en el bucket que NO son .webp
 *
 * Uso:
 *   node check-non-webp.js
 */

const { createAdminClient } = require("./supabase-admin-client");

const BUCKET = "products-images";

const supabase = createAdminClient();

async function listFolders() {
  const { data, error } = await supabase.storage
    .from(BUCKET)
    .list("", { limit: 1000 });
  if (error) throw new Error("Error listando raíz: " + error.message);
  return data || [];
}

async function listFilesInFolder(folder) {
  const { data, error } = await supabase.storage
    .from(BUCKET)
    .list(folder, { limit: 1000 });
  if (error) throw new Error(`Error listando ${folder}: ` + error.message);
  return (data || []).filter((i) => i.id !== null);
}

function formatBytes(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}

async function main() {
  const rootItems = await listFolders();

  const folders = rootItems.filter((i) => i.id === null);
  const rootFiles = rootItems.filter((i) => i.id !== null);

  const nonWebp = [];
  let totalSize = 0;

  // Archivos sueltos en la raíz
  for (const f of rootFiles) {
    if (!f.name.toLowerCase().endsWith(".webp")) {
      const size = f.metadata?.size ?? 0;
      nonWebp.push({ path: f.name, size });
      totalSize += size;
    }
  }

  // Archivos dentro de carpetas
  for (const folder of folders) {
    const files = await listFilesInFolder(folder.name);
    for (const f of files) {
      if (!f.name.toLowerCase().endsWith(".webp")) {
        const size = f.metadata?.size ?? 0;
        nonWebp.push({ path: `${folder.name}/${f.name}`, size });
        totalSize += size;
      }
    }
  }

  if (nonWebp.length === 0) {
    console.log("✅ No hay archivos que no sean .webp. Todo limpio.");
    return;
  }

  console.log(`⚠️  Archivos NO webp encontrados: ${nonWebp.length}\n`);
  for (const f of nonWebp) {
    console.log(`  ${f.path}  (${formatBytes(f.size)})`);
  }
  console.log(`\n  Peso total de archivos no-webp: ${formatBytes(totalSize)}`);
  console.log(`\n💡 Para borrarlos, ejecutá: node check-non-webp.js --delete`);

  if (process.argv.includes("--delete")) {
    console.log("\n🗑️  Borrando archivos no-webp...");
    let deleted = 0;
    for (const f of nonWebp) {
      const { error } = await supabase.storage.from(BUCKET).remove([f.path]);
      if (error) {
        console.error(`  ✗ ${f.path}: ${error.message}`);
      } else {
        console.log(`  ✓ ${f.path}`);
        deleted++;
      }
    }
    console.log(`\n✅ Borrados: ${deleted}/${nonWebp.length} — Espacio liberado: ${formatBytes(totalSize)}`);
  }
}

main().catch((err) => {
  console.error("❌ Error:", err.message);
  process.exit(1);
});
