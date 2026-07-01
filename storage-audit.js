/**
 * storage-audit.js
 *
 * Lista TODOS los buckets de Supabase y el peso de cada uno.
 *
 * Uso: node storage-audit.js
 */

const { createClient } = require("@supabase/supabase-js");

const SUPABASE_URL = "https://zjvpzqhbekxnwxdczpof.supabase.co";
const SUPABASE_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpqdnB6cWhiZWt4bnd4ZGN6cG9mIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NDAyNTI5OSwiZXhwIjoyMDg5NjAxMjk5fQ.kPO2Ku3lAI-c5wC7STD-AIRcI6ww9PKG60Vsn_UJIu4";

const supabase = createClient(SUPABASE_URL, SUPABASE_KEY);

function formatBytes(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
}

async function getBucketSize(bucketId) {
  let totalSize = 0;
  let totalFiles = 0;

  async function scanFolder(prefix) {
    const { data, error } = await supabase.storage
      .from(bucketId)
      .list(prefix, { limit: 1000 });
    if (error || !data) return;

    for (const item of data) {
      const path = prefix ? `${prefix}/${item.name}` : item.name;
      if (item.id === null) {
        // Es una carpeta, escanear recursivamente
        await scanFolder(path);
      } else {
        const size = item.metadata?.size ?? 0;
        totalSize += size;
        totalFiles++;
      }
    }
  }

  await scanFolder("");
  return { totalSize, totalFiles };
}

async function main() {
  // Listar todos los buckets
  const { data: buckets, error } = await supabase.storage.listBuckets();
  if (error) throw new Error("Error listando buckets: " + error.message);

  if (!buckets || !buckets.length) {
    console.log("No se encontraron buckets.");
    return;
  }

  console.log(`📊 Buckets encontrados: ${buckets.length}\n`);

  let grandTotal = 0;
  const results = [];

  for (const bucket of buckets) {
    process.stdout.write(`  Escaneando ${bucket.id}...`);
    const { totalSize, totalFiles } = await getBucketSize(bucket.id);
    results.push({ id: bucket.id, totalFiles, totalSize, public: bucket.public });
    grandTotal += totalSize;
    process.stdout.write(` ${formatBytes(totalSize)}\n`);
  }

  results.sort((a, b) => b.totalSize - a.totalSize);

  console.log("\n─────────────────────────────────");
  console.log("  RESUMEN (de mayor a menor):\n");
  for (const r of results) {
    const pub = r.public ? "público" : "privado";
    console.log(`  ${r.id.padEnd(25)} ${String(r.totalFiles).padStart(5)} archivos   ${formatBytes(r.totalSize).padStart(10)}   (${pub})`);
  }
  console.log("\n─────────────────────────────────");
  console.log(`  TOTAL: ${formatBytes(grandTotal)}`);
}

main().catch((err) => {
  console.error("❌ Error:", err.message);
  process.exit(1);
});
