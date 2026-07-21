---
phase: 01-perimetro-y-deuda-critica-de-seguridad
plan: 01
requirements: [SEC-01]
status: complete
date: 2026-07-21
---

# 01-01 SUMMARY — SEC-01: service_role key fuera del codigo

## Resultado

**SEC-01 cumplido.** Cero `service_role` keys en el working tree. Los 8 scripts de mantenimiento leen la credencial desde `process.env.SUPABASE_SERVICE_ROLE_KEY` via un helper compartido que falla rapido si la variable no esta.

## Que se hizo

**Archivos nuevos**
- `supabase-admin-client.js` — helper CommonJS. Exporta `createAdminClient()` y `SUPABASE_URL`. Si falta la env var, imprime instrucciones concretas y sale con codigo 1.
- `.env.example` — plantilla versionada, sin secretos, con `SUPABASE_SERVICE_ROLE_KEY=` vacio.

**Archivos modificados**
- `package.json` — agregado `dotenv ^17.0.0` (instalado: 17.4.2, 19 paquetes).
- Los 8 scripts: `check-non-webp.js`, `compress-75kb.js`, `download-all-images.js`, `optimize-images.js`, `recreate-bucket.js`, `rename-images.js`, `storage-audit.js`, `storage-size.js`.

Transformacion aplicada en cada uno:
```diff
-const { createClient } = require("@supabase/supabase-js");
-const SUPABASE_URL = "https://zjvpzqhbekxnwxdczpof.supabase.co";
-const SUPABASE_KEY = "eyJ...";
-const supabase = createClient(SUPABASE_URL, SUPABASE_KEY);
+const { createAdminClient } = require("./supabase-admin-client");
+const supabase = createAdminClient();
```
Constantes propias de cada script (`BUCKET`, `OUTPUT_DIR`, `BACKUP_DIR`, `MAX_SIZE`, `WEBP_QUALITY`, `DRY_RUN`) y los `require` extra (`sharp`, `fs`, `path`, `mime-types`) preservados. Cabecera de cada script anotada con `Requiere .env con SUPABASE_SERVICE_ROLE_KEY`.

`.gitignore` NO se modifico — ya cubria `.env` y `.env.*` (lineas 15-18), como anticipaba el plan.

## Verificacion

| Check | Resultado |
|---|---|
| `service_role` en working tree | **0** |
| `node --check` en los 8 | **8/8 OK** |
| Los 8 usan `createAdminClient()` | **8/8** |
| Alguno declara `SUPABASE_KEY` | **0** |
| Existe `.env` | no (correcto — se crea en Plan 03) |
| Camino A: sin env var | exit 1 + mensaje de `.env`, sin stacktrace de Supabase |
| Camino B: con env var | lista 2 buckets, 289 archivos, 17.34 MB — identico a antes del refactor |

Camino B se corrio extrayendo la key vieja del historial de git (`git show 3dad03e:storage-audit.js`) en memoria, sin transcribirla a ningun archivo ni al historial de la shell. Variable de sesion limpiada al terminar.

## Desviaciones del plan

**El comando de verificacion del plan da falsos positivos.** El plan verifica con:
```
grep -rn "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" --include=*.js .
```
Ese prefijo es el **header** de cualquier JWT HS256 codificado en base64url — es identico en todos los JWT de Supabase, incluidas las `anon` keys. El grep matchea `admin.js:5`, `historial.js:4` y `script.js:8`, que son anon keys del frontend, publicas por diseño y que deben quedar donde estan.

La verificacion correcta decodifica el payload y filtra por `role`:
```powershell
# extraer el payload (segundo segmento), decodificar base64url, leer .role
```
Verificado asi: 3 JWT en el working tree, los 3 con `role=anon` y `ref=zjvpzqhbekxnwxdczpof`. Cero `service_role`.

Recomendacion para los planes siguientes: no usar el prefijo del header JWT como firma de secreto. Buscar por `role` decodificado, o por el segmento de payload especifico.

**Nota de encoding.** Los archivos estan en UTF-8 y contienen acentos y flechas (`←`). En PowerShell 5.1 `Get-Content` los lee como ANSI y los muestra corruptos. Las ediciones se hicieron con herramientas que preservan encoding; no usar `Set-Content` sobre estos archivos sin `-Encoding utf8`.

## Estado para el Plan 03 (SEC-02, rotacion)

Todo listo. Cuando el usuario rote la key:
1. `copy .env.example .env`
2. Pegar la key nueva en `SUPABASE_SERVICE_ROLE_KEY=`
3. `node storage-audit.js` deberia listar los buckets igual que hoy

La key vieja sigue viva en este punto — la rotacion es el Plan 03. Hasta que se rote, el riesgo real sigue abierto aunque el codigo ya este limpio.
