/**
 * make-thumbnails.js
 *
 * Requiere .env con SUPABASE_SERVICE_ROLE_KEY (ver .env.example).
 *
 * Genera una MINIATURA por cada imagen del bucket, redimensionada a
 * THUMB_MAX px (lado mayor) en WebP. La miniatura se guarda al lado de la
 * original con el sufijo "_sm":
 *
 *   631/1.webp   (original 1667px, se usa para el zoom en alta calidad)
 *   631/1_sm.webp  (miniatura ~700px, la que carga la grilla → rápido)
 *
 * NO toca la columna `images` de products ni borra las originales: el front
 * deriva la URL "_sm" solo (ver thumbUrl() en script.js) y usa la original
 * para el zoom.
 *
 * Uso:
 *   node make-thumbnails.js            ← dry-run (solo muestra qué haría)
 *   node make-thumbnails.js --run      ← genera y sube las miniaturas
 *   node make-thumbnails.js --run --force  ← regenera aunque ya existan
 *
 * Requiere:
 *   npm install @supabase/supabase-js sharp
 */

const { createAdminClient } = require("./supabase-admin-client");
const sharp = require("sharp");

const BUCKET = "products-images";
const THUMB_MAX = 700; // lado mayor de la miniatura (px)
const THUMB_QUALITY = 80; // calidad WebP de la miniatura
const THUMB_SUFFIX = "_sm";

const DRY_RUN = !process.argv.includes("--run");
const FORCE = process.argv.includes("--force");

const supabase = createAdminClient();

const IMAGE_EXTS = new Set([
  ".jpg",
  ".jpeg",
  ".png",
  ".webp",
  ".gif",
  ".bmp",
  ".tiff",
]);

function getExt(filename) {
  const dot = filename.lastIndexOf(".");
  return dot === -1 ? "" : filename.substring(dot).toLowerCase();
}

function stripExt(filename) {
  const dot = filename.lastIndexOf(".");
  return dot === -1 ? filename : filename.substring(0, dot);
}

function isThumbName(name) {
  return stripExt(name).toLowerCase().endsWith(THUMB_SUFFIX);
}

function formatBytes(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}

async function listFolders() {
  const { data, error } = await supabase.storage
    .from(BUCKET)
    .list("", { limit: 100000 });
  if (error) throw new Error("Error listando carpetas: " + error.message);
  // Las carpetas vienen con id === null.
  return (data || []).filter((i) => i.id === null).map((i) => i.name);
}

async function listFilesInFolder(folder) {
  const { data, error } = await supabase.storage
    .from(BUCKET)
    .list(folder, { limit: 100000 });
  if (error) throw new Error(`Error listando ${folder}: ` + error.message);
  return (data || []).filter(
    (i) => i.id !== null && IMAGE_EXTS.has(getExt(i.name)),
  );
}

async function downloadFile(path) {
  const { data, error } = await supabase.storage.from(BUCKET).download(path);
  if (error) throw new Error(`Error descargando ${path}: ` + error.message);
  return Buffer.from(await data.arrayBuffer());
}

async function uploadFile(path, buffer) {
  const { error } = await supabase.storage
    .from(BUCKET)
    .upload(path, buffer, { contentType: "image/webp", upsert: true });
  if (error) throw new Error(`Error subiendo ${path}: ` + error.message);
}

async function main() {
  console.log(
    DRY_RUN
      ? "🔍 DRY RUN — no se sube nada (usá --run para aplicar)\n"
      : `🚀 Generando miniaturas (${THUMB_MAX}px, q${THUMB_QUALITY})${FORCE ? " [--force]" : ""}\n`,
  );

  const folders = await listFolders();
  console.log(`Carpetas encontradas: ${folders.length}\n`);

  let generadas = 0;
  let saltadas = 0;
  let errores = 0;
  let totalIn = 0;
  let totalOut = 0;

  for (const folder of folders) {
    const files = await listFilesInFolder(folder);
    if (!files.length) continue;

    const nombres = new Set(files.map((f) => f.name));
    // Solo las originales (no las que ya son _sm).
    const originales = files.filter((f) => !isThumbName(f.name));

    for (const file of originales) {
      const base = stripExt(file.name);
      const thumbName = `${base}${THUMB_SUFFIX}.webp`;
      const thumbPath = `${folder}/${thumbName}`;
      const srcPath = `${folder}/${file.name}`;

      if (nombres.has(thumbName) && !FORCE) {
        saltadas++;
        continue;
      }

      if (DRY_RUN) {
        console.log(`   ${srcPath} → ${thumbName}`);
        generadas++;
        continue;
      }

      try {
        const original = await downloadFile(srcPath);
        const thumb = await sharp(original)
          .resize({
            width: THUMB_MAX,
            height: THUMB_MAX,
            fit: "inside",
            withoutEnlargement: true,
          })
          .webp({ quality: THUMB_QUALITY })
          .toBuffer();

        await uploadFile(thumbPath, thumb);

        totalIn += original.length;
        totalOut += thumb.length;
        generadas++;

        const pct =
          original.length > 0
            ? Math.round((1 - thumb.length / original.length) * 100)
            : 0;
        console.log(
          `   ✓ ${thumbPath}  ${formatBytes(original.length)} → ${formatBytes(thumb.length)}  (-${pct}%)`,
        );
      } catch (err) {
        console.error(`   ✗ ${srcPath}: ${err.message}`);
        errores++;
      }
    }
  }

  console.log("\n─────────────────────────────────");
  if (DRY_RUN) {
    console.log(`✅ Dry run completo.`);
    console.log(`   ${generadas} miniaturas se generarían.`);
    console.log(`   ${saltadas} ya existen (se saltarían; usá --force para rehacerlas).`);
    console.log("\nEjecutá con --run para generarlas.");
  } else {
    const pct = totalIn > 0 ? Math.round((1 - totalOut / totalIn) * 100) : 0;
    console.log(`✅ Listo.`);
    console.log(`   Miniaturas generadas : ${generadas}`);
    console.log(`   Ya existían (saltadas): ${saltadas}`);
    console.log(`   Errores              : ${errores}`);
    console.log(`   Peso originales      : ${formatBytes(totalIn)}`);
    console.log(`   Peso miniaturas      : ${formatBytes(totalOut)}  (-${pct}%)`);
  }
}

main().catch((err) => {
  console.error("\n❌ Error fatal:", err.message);
  process.exit(1);
});
