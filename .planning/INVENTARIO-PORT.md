# Inventario del port PaginaLK -> Tierra Nativa

Insumo para las Phases 4 y 5. Levantado el 2026-07-21 contra
`Y:\AA IT\Elias-main\PaginaLK-main\PaginaLK-main`.

## Hallazgo que corrige el alcance: OSA **es** el Pedido Automatico

El roadmap los trataba como dos exclusiones separadas ("Modulo OSA" y "Pedido automatico `pa_*`").
Son **el mismo modulo**:

- `mayorista.html:1533-1610` define `osaFormatModal`, un modal con dos opciones — "Formato regular"
  y **"Pedido Automatico"** (`osaFormatLinkLabel`, linea 1551) — donde la segunda apunta a
  `osa/index.html` (lineas 212 y 1548).
- La app vive en `osa/` (4 archivos: `index.html`, `css/styles.css`, `js/app.js`, `js/store.js`)
  mas `admin-osa.js` en la raiz.
- Su backend son las tablas `pa_*` (`pa_articulos`, `pa_entregas`, `pa_ventas`, `pa_ajustes`,
  `pa_config`) y las `osa_*`.

Por eso el grep de `pedido_automatico` / `pa_` sobre el codigo de LK devuelve **cero**: el namespace
del frontend es `osa`, el de la base es `pa_` + `osa_`. Excluir OSA excluye el Pedido Automatico
automaticamente. No son dos tareas.

## Volumen real del strip: chico

| Modulo | script.js | admin.js | admin.html | mayorista.html | index.html | Otros |
|---|---|---|---|---|---|---|
| OSA / Pedido Automatico | 3 | — | 6 | 17 | 2 | `admin-osa.js`, `osa/` (4 archivos) |
| Torres y Liva | 2 | — | — | — | 5 | `tyl/index.html` |
| Bot WhatsApp | 4 | 6 | 2 | — | 7 | — |
| Chef | — | — | — | — | — | `admin-supercot.js` (6) |

**~60 lineas de referencias** en total, mas archivos y assets completos. Es mucho menos de lo que
sugeria el tamano de los modulos en la base de datos (~30 tablas). La mayor parte del codigo de
esos modulos vive en archivos propios, no entremezclado.

## Matiz importante: en `index.html` NO son modulos, son logos de clientes

`index.html:372-387` y `:520-543` tienen a OSA (`osa_logo.png`, link a osadistribuidora.com.ar) y
Torres y Liva (`torresyliva_logo.png`, link a torresyliva.com) dentro del carrusel de **clientes de
Loekemeyer**.

**No se borran y listo: se reemplazan por los clientes de Tierra Nativa.** Borrarlos deja huecos en
el carrusel. Esto es BRAND-04, no PORT-08 — son dos tareas distintas sobre las mismas lineas, y hay
que coordinarlas o una pisa a la otra.

Logos de clientes de LK presentes en el repo, todos a reemplazar:
`changomas_logo.png`, `coto_logo.png`, `dia_logo.png`, `jumbo_logo.png`, `laanonima_logo.png`,
`msanchez_logo.png`, `mullerymuller_logo.png`, `noblex_logo.png`, `osa_logo.png`,
`torresyliva_logo.png`.

**Pendiente del usuario:** quienes son los clientes de Tierra Nativa que van en ese carrusel, y sus
logos. Sin eso la seccion queda vacia.

## Diferencia de estructura de carpetas

| | LK | Elias |
|---|---|---|
| CSS | raiz (`styles.css`) **y** `css/` | solo `css/` |
| Imagenes | raiz (`logo.png`, `img_landing.png`) | `img/` |
| Videos | raiz (`video_*.mp4`) | no tiene |
| GIFs | raiz **y** `gif/` | `gif/` |
| PDF | raiz (`catalogo.pdf`) | `pdf/` |

LK tiene los assets duplicados entre la raiz y subcarpetas. **Elias tiene la estructura mas limpia.**
Al portar hay que reescribir las rutas de los HTML de LK para que apunten a las subcarpetas de Elias,
no copiar el desorden de LK. Afecta a todos los `<img src>`, `<link href>` y `url()` de CSS.

Riesgo concreto: copiar `mayorista.html` de LK tal cual deja rutas como `logo.png` que en Elias
tienen que ser `img/logo.png`. Son cientos de referencias — hay que hacerlo con reemplazo
sistematico y verificar que no quede ningun 404.

## Archivos que Elias NO tiene y el port trae

**Codigo:** `sugerencias.html`, `sugerencias.js`, `sugerencias.css`, `analisis-cobranzas.html`,
`analisis-cobranzas.js`, `analisis-venta-cliente.js`, `carga-pedidos.html`, `argentina-map-data.js`,
`excel-parser-smart.js`, `version.js`, `robots.txt`, `serve.ps1`.

Los 4 que `admin.html` referencia y hoy dan 404 en Elias (`version.js`, `excel-parser-smart.js`,
`argentina-map-data.js`, `analisis-venta-cliente.js`) **existen todos en LK** — el port resuelve
PORT-06 sin trabajo extra.

**A NO portar:** `admin-osa.js`, `osa/`, `tyl/`, y los `.sql` sueltos de LK
(`crear_ventas_chef.sql`, `impactar_ventas_chef_en_sales_lines.sql`,
`programar_pedido_automatico.sql`, `recordatorio_mail_ventas.sql`,
`add_module_usage_tracking.sql`, `add_order_source_tracking.sql`,
`estadistica_madre_cache.sql`) — son de modulos excluidos o ya aplicados en LK, no en Elias.

## Archivos exclusivos de Elias — NO pisar

- `supabase-admin-client.js` + los 8 scripts de mantenimiento de storage (ya refactorizados en
  la Phase 1, SEC-01). LK no los tiene.
- `.env.example`, `package.json`, `package-lock.json`. LK no tiene `package.json`.
- `migration_tn*.sql` — obsoletos, se borran en DATA-03. No portar los de LK en su lugar.

## Diferencia de tamano por archivo

| Archivo | Elias | LK | Delta |
|---|---|---|---|
| `script.js` | 117 KB | 369 KB | **+252 KB** |
| `admin.js` | 282 KB | 309 KB | +28 KB |
| `mayorista.html` | 27 KB | 64 KB | +37 KB |
| `admin.html` | 91 KB | 98 KB | +7 KB |
| `index.html` | 19 KB | 30 KB | +11 KB |
| `historial.js` | 9 KB | 19 KB | +9 KB |
| `admin-supercot.js` | 125 KB | 136 KB | +10 KB |
| `web.config` | 0.5 KB | 88 KB | +88 KB |

`script.js` triplica su tamano: ahi esta el grueso de la funcionalidad que Elias nunca recibio.

### `web.config` de LK: NO portar. Esta corrupto.

Dos razones independientes, cualquiera alcanza:

1. El servidor de Tierra Nativa es **Apache**. `web.config` es de IIS y no hace nada.
2. **El archivo de LK no es XML: es JavaScript.** Verificado 2026-07-21.

Sobre el punto 2. `PaginaLK-main/web.config` pesa 88 KB y tiene 2654 lineas. No parsea como XML
(`[xml]` falla con `No se puede convertir el valor ""use strict";`). Su contenido es codigo de
`script.js`: en las lineas 551-566 esta `loadProductsFromDB()` completa. Alguien guardo `script.js`
encima de `web.config` en algun momento.

Los 88 KB de diferencia contra el `web.config` de Elias (0.5 KB) no eran "configuracion IIS
elaborada". Eran un archivo pisado.

**Aviso para Loekemeyer, fuera del alcance de este proyecto:** si el sitio de LK corre sobre IIS,
un `web.config` invalido normalmente devuelve HTTP 500 en todo el sitio. Que LK funcione sugiere
que o no esta en IIS, o ese archivo no esta desplegado en su webroot. Vale que alguien lo mire del
lado de LK; nosotros solo tenemos que no copiarlo.

**Utilidad colateral:** las lineas 554-559 de ese archivo corrupto muestran
`get_products_public_sorted` invocada con `{ sort_mode: sortMode }` dentro de la rama `if (!logged)`
—o sea, contexto anonimo—. Corrobora de forma independiente el riesgo de GRANT que detecto la
planificacion de la Phase 3.

## Constantes a reapuntar (BRAND-01/02/03)

| Que | En LK | En Tierra Nativa |
|---|---|---|
| `SUPABASE_URL` | `kwkclwhmoygunqmlegrg` | `zjvpzqhbekxnwxdczpof` |
| anon key | la de LK | la de TN (ya presente en el `script.js`/`admin.js`/`historial.js` actuales de Elias — extraerlas de ahi antes de pisarlos) |
| `CATEGORY_ORDER` | utensilios de cocina | Cuadros, Deco, Portaretratos, Importados |
| Subcategorias | cuelgan de Utensilios | cuelgan de **Cuadros** (155 productos con subcategoria) |
| Edge functions | `kwkclwhmoygunqmlegrg.functions.supabase.co` | verificar que existan en el proyecto de TN |
| Cliente especial | `cod_cliente === "5000"` (modo solo precio de lista) | **confirmar con el usuario si aplica** |
| `web_order_discount` | fallback `0.02` | en TN `app_settings` dice `0.00` |

**Orden critico:** extraer la anon key de Tierra Nativa de los archivos actuales de Elias **antes**
de sobrescribirlos con los de LK. Si se pisan primero, hay que ir a buscarla al dashboard.
(Mitigado: estan en git, commit `3dad03e`.)

## Edge functions: riesgo RESUELTO (verificado 2026-07-21)

Tierra Nativa **si tiene** desplegadas las funciones que el codigo portado necesita:

| Slug | verify_jwt | Para que |
|---|---|---|
| `sheets-proxy` | true | Empuja pedidos confirmados a Google Sheets |
| `sheets-entregas-proxy` | true | Idem, entregas |
| `admin-otp` | true | **2FA del panel admin (SEC-04)** |
| `google-sheets` | true | Usada por los cotizadores |
| `notify-new-address` | true | Notificacion de sucursal nueva |
| `subir-pedido-pdf` | true | PDF del pedido |
| `migrar-customers` | true | Migracion puntual |

El port no requiere desplegar nada nuevo. Que exista `admin-otp` es relevante: confirma que SEC-04
(reactivar el 2FA) es viable de verdad y no queda a medias por falta de backend.

**Pendiente de confirmar:** que `sheets-proxy` y `sheets-entregas-proxy` de Tierra Nativa apunten a
un Google Sheet **de Tierra Nativa** y no al de Loekemeyer. El slug coincide, pero el Sheet destino
esta dentro del codigo de la funcion. Si apunta al de LK, los pedidos de Tierra Nativa van a caer en
la planilla de otra empresa. Revisar con `get_edge_function` antes de la Phase 4.

### Hallazgo colateral: funcion duplicada sin autenticacion

Hay **dos** funciones con `name: "google-sheets"`:

| id (parcial) | slug | name | verify_jwt |
|---|---|---|---|
| `c9c42163` | `google-sheets` | google-sheets | **true** |
| `41b59d7e` | `quick-task` | google-sheets | **false** |

El frontend invoca por **slug** (`/functions/v1/google-sheets`), asi que usa la primera, que si pide
JWT. La segunda, con slug `quick-task`, quedo huerfana **y sin verificacion de JWT**: cualquiera que
sepa la URL puede invocarla sin autenticarse.

Es el mismo patron que la auditoria encontro en LK con `notify-m3-mismatch`. Severidad a determinar
segun que haga el codigo de `quick-task` — si escribe en un Sheet o toca la base, es un endpoint
abierto. Si es un stub de prueba, es solo basura a limpiar.

**Accion:** inspeccionar `quick-task` con `get_edge_function` y, salvo que tenga un uso legitimo,
eliminarla. No estaba en el roadmap; candidata a sumarse a la Phase 3 (endurecimiento) o al backlog.
