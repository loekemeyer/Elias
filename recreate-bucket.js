/**
 * recreate-bucket.js
 *
 * Requiere .env con SUPABASE_SERVICE_ROLE_KEY (ver .env.example).
 *
 * Borra el bucket products-images y lo recrea, luego sube todas
 * las imágenes desde la carpeta backup-images/.
 *
 * IMPORTANTE: ejecutá download-all-images.js primero para tener el backup.
 *
 * Uso:
 *   node recreate-bucket.js          ← dry-run (verifica el backup)
 *   node recreate-bucket.js --run    ← ejecuta los cambios reales
 */

const { createAdminClient } = require("./supabase-admin-client");
const fs = require("fs");
const path = require("path");
const mime = require("mime-types");

const BUCKET = "products-images";
const BACKUP_DIR = path.join(__dirname, "backup-images");

const DRY_RUN = !process.argv.includes("--run");
const supabase = createAdminClient();

function formatBytes(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}

function getContentType(filePath) {
  return mime.lookup(filePath) || "application/octet-stream";
}

function collectFiles(dir, base) {
  let files = [];
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    const relativePath = base ? `${base}/${entry.name}` : entry.name;
    if (entry.isDirectory()) {
      files = files.concat(collectFiles(fullPath, relativePath));
    } else {
      files.push({ localPath: fullPath, storagePath: relativePath, size: fs.statSync(fullPath).size });
    }
  }
  return files;
}

async function emptyBucket() {
  async function deleteFolder(prefix) {
    const { data, error } = await supabase.storage.from(BUCKET).list(prefix, { limit: 1000 });
    if (error || !data) return;

    const folders = data.filter((i) => i.id === null);
    const files = data.filter((i) => i.id !== null);

    // Borrar archivos en este nivel
    if (files.length) {
      const paths = files.map((f) => prefix ? `${prefix}/${f.name}` : f.name);
      const { error: delErr } = await supabase.storage.from(BUCKET).remove(paths);
      if (delErr) console.error(`   Error borrando en ${prefix || "raíz"}: ${delErr.message}`);
    }

    // Recursivo en subcarpetas
    for (const folder of folders) {
      const folderPath = prefix ? `${prefix}/${folder.name}` : folder.name;
      await deleteFolder(folderPath);
    }
  }

  await deleteFolder("");
}

async function main() {
  // Verificar que el backup existe
  if (!fs.existsSync(BACKUP_DIR)) {
    console.error("❌ No se encontró la carpeta backup-images/");
    console.error("   Ejecutá primero: node download-all-images.js");
    process.exit(1);
  }

  const files = collectFiles(BACKUP_DIR, "");
  const totalSize = files.reduce((sum, f) => sum + f.size, 0);

  console.log(`📂 Backup encontrado: ${files.length} archivos (${formatBytes(totalSize)})\n`);

  if (DRY_RUN) {
    console.log("🔍 DRY RUN — verificación del backup:\n");
    const folders = new Set(files.map((f) => f.storagePath.split("/")[0]));
    console.log(`   Carpetas: ${folders.size}`);
    console.log(`   Archivos: ${files.length}`);
    console.log(`   Peso:     ${formatBytes(totalSize)}`);
    console.log(`\n✅ Todo listo. Ejecutá con --run para recrear el bucket.`);
    return;
  }

  // Paso 1: Vaciar el bucket actual
  console.log("🗑️  Paso 1/3: Vaciando bucket actual...");
  await emptyBucket();
  console.log("   ✓ Bucket vaciado.\n");

  // Paso 2: Borrar y recrear el bucket
  console.log("🔄 Paso 2/3: Recreando bucket...");
  const { error: delErr } = await supabase.storage.deleteBucket(BUCKET);
  if (delErr) console.warn(`   ⚠ No se pudo borrar bucket: ${delErr.message} — continuando...`);

  const { error: createErr } = await supabase.storage.createBucket(BUCKET, {
    public: true,
    fileSizeLimit: 5 * 1024 * 1024, // 5 MB
  });
  if (createErr) {
    // Si el bucket ya existe (porque no se pudo borrar), seguimos con upload
    if (!createErr.message.includes("already exists")) {
      throw new Error("Error creando bucket: " + createErr.message);
    }
    console.log("   ⚠ Bucket ya existía, subiendo archivos igualmente...\n");
  } else {
    console.log("   ✓ Bucket recreado.\n");
  }

  // Paso 3: Subir todos los archivos
  console.log("📤 Paso 3/3: Subiendo archivos...");
  let uploaded = 0;
  let errors = 0;

  for (const file of files) {
    try {
      const buffer = fs.readFileSync(file.localPath);
      const contentType = getContentType(file.localPath);

      const { error: upErr } = await supabase.storage
        .from(BUCKET)
        .upload(file.storagePath, buffer, { contentType, upsert: true });

      if (upErr) throw new Error(upErr.message);
      uploaded++;
      process.stdout.write(`\r   Subido: ${uploaded}/${files.length}`);
    } catch (err) {
      console.error(`\n   ✗ ${file.storagePath}: ${err.message}`);
      errors++;
    }
  }

  console.log(`\n\n─────────────────────────────────`);
  console.log(`✅ Bucket recreado exitosamente.`);
  console.log(`   Subidos  : ${uploaded}`);
  console.log(`   Errores  : ${errors}`);
  console.log(`   Peso real: ${formatBytes(totalSize)}`);
}

main().catch((err) => {
  console.error("❌ Error:", err.message);
  process.exit(1);
});
