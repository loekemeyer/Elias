# Requirements — Milestone v1: Port desde PaginaLK

Derivados de `.planning/PROJECT.md`. Un requisito por capacidad observable.

## v1 Requirements

### Seguridad (SEC)

- [ ] **SEC-01**: La `service_role` key de Supabase deja de estar hardcodeada en los 8 scripts de mantenimiento; se lee desde variable de entorno
- [ ] **SEC-02**: La `service_role` key expuesta queda rotada en Supabase, invalidando la que está en el historial de git
- [ ] **SEC-03**: Los scripts de mantenimiento de storage no son descargables por HTTP desde el sitio publicado
- [ ] **SEC-04**: El admin con privilegios PPP no puede entrar al panel sin segundo factor
- [ ] **SEC-05**: Los tres uploads de Excel que resetean deuda, límite de crédito y plazo de pago piden confirmación explícita antes de escribir, y validan que el parseo produjo filas antes de tocar la cartera
- [ ] **SEC-06**: Un `business_name` con HTML malicioso cargado por Excel no ejecuta código al renderizar la grilla de clientes
- [ ] **SEC-07**: El PIN de cliente se genera con `crypto.getRandomValues()` en lugar de `Math.random()`
- [ ] **SEC-08**: La separación de privilegios entre admin PPP y admin común deja de depender solo de CSS

### Infraestructura (INFRA)

- [ ] **INFRA-01**: Está documentado dónde vive el webroot del sitio y por qué mecanismo se despliega
- [ ] **INFRA-02**: `web.config` bloquea el acceso HTTP a scripts de mantenimiento, `.sql` y archivos de planificación
- [ ] **INFRA-03**: El sitio responde por HTTPS con certificado válido

### Port del frontend (PORT)

- [ ] **PORT-01**: `script.js`, `mayorista.html` y `css/styles.css` provienen de PaginaLK y el catálogo carga con los 336 productos de Tierra Nativa
- [ ] **PORT-02**: `admin.js`, `admin.html` y `css/admin.css` provienen de PaginaLK y el panel abre sin errores de consola
- [ ] **PORT-03**: `index.html`, `script.index.js` y `css/styles.index.css` provienen de PaginaLK
- [ ] **PORT-04**: `historial.html` y `historial.js` provienen de PaginaLK
- [ ] **PORT-05**: La página de sugerencias (`sugerencias.html`, `sugerencias.js`, `sugerencias.css`) existe y consume las RPC `sugerencias_cliente` y `novedades_marca`
- [ ] **PORT-06**: Los 6 scripts que `admin.html` referencia y hoy dan 404 (`version.js`, `excel-parser-smart.js`, `argentina-map-data.js`, `analisis-venta-cliente.js`) están presentes o su referencia fue eliminada
- [ ] **PORT-07**: Un cliente mayorista puede loguearse, navegar el catálogo, armar un carrito y confirmar un pedido de punta a punta
- [ ] **PORT-08**: Ningún archivo, script ni referencia de los módulos excluidos (OSA, TyL, bot WhatsApp, Chef, pedido automático) queda en el repo

### Cotizadores (COT)

- [ ] **COT-01**: `admin-supercot.js` y `admin-excel-krikos.js` están portados desde PaginaLK
- [ ] **COT-02**: El path que envía pedidos al proyecto Supabase de Chef está eliminado; todo se resuelve contra el Supabase de Tierra Nativa
- [ ] **COT-03**: Un fallo del RPC de submit aborta el flujo en vez de fabricar un número de pedido sintético

### Branding y configuración (BRAND)

- [ ] **BRAND-01**: Todas las declaraciones de `SUPABASE_URL` y anon key apuntan al proyecto de Tierra Nativa
- [ ] **BRAND-02**: `CATEGORY_ORDER` refleja la taxonomía de Tierra Nativa (Cuadros, Deco, Portaretratos, Importados)
- [ ] **BRAND-03**: El orden de subcategorías cuelga de Cuadros, no de Utensilios
- [ ] **BRAND-04**: Logos, imágenes, videos y textos institucionales son de Tierra Nativa, sin rastros de Loekemeyer
- [ ] **BRAND-05**: `sitemap.xml` declara `https://` y las URLs públicas reales; existe `robots.txt`
- [ ] **BRAND-06**: Las páginas privadas (`historial`, `sugerencias`, `admin`) llevan `noindex`

### Base de datos (DATA)

- [ ] **DATA-01**: Los overloads duplicados de `get_my_linked_customers` y `get_products_public_sorted` están resueltos, y llamarlas ya no da `function is not unique`
- [ ] **DATA-02**: Las RPC `SECURITY DEFINER` de reporting validan que quien llama sea admin
- [ ] **DATA-03**: Los archivos `migration_tn*.sql` obsoletos fueron eliminados del repo
- [ ] **DATA-04**: El módulo `fichaje_*` sigue funcionando: sus 6 tablas y 30+ RPCs quedan intactas

### Correcciones funcionales (FIX)

- [ ] **FIX-01**: Un doble click en "Confirmar pedido" no genera pedidos duplicados
- [ ] **FIX-02**: Los errores de Supabase en borrado y edición de sucursales se muestran al admin en vez de un toast de éxito
- [ ] **FIX-03**: El borrado masivo de tracking verifica el resultado antes de insertar la tanda nueva
- [ ] **FIX-04**: Cambiar de pestaña o volver del historial no borra la sucursal ya elegida en el checkout

## v2 (diferido)

- Paginación del catálogo y del historial (hoy las queries chocan contra el límite de 1000 filas de PostgREST sin avisar)
- Debounce en los buscadores del catálogo
- Optimización de imágenes pesadas (`logo.png` 1.4 MB, `img_landing.png` 1.3 MB, `no-image.jpg` 600 KB)
- Accesibilidad: controles de navegación con `<button>` en vez de `<a>` sin `href`, foco atrapado en modales
- Hash del PIN de cliente en base (hoy se guarda en texto plano)
- Consolidar los 5 helpers de escape HTML duplicados en `admin.js`
- Deduplicar el pipeline de envío a Google Sheets, hoy triplicado

## Out of Scope

- **Módulo OSA** — vertical de Loekemeyer, sin uso en Tierra Nativa
- **Módulo Torres y Liva** — cliente específico de LK
- **Bot de WhatsApp** — ~20 tablas, decisión explícita
- **Integración Chef** — los precios salen del Supabase propio
- **Pedido automático (`pa_*`)** — vertical de LK
- **Modificar el módulo `fichaje_*`** — es de Elias, funciona, y su frontend está fuera de este repo
- **Modernizar la sintaxis de `admin.js`** — es consistente dentro de su archivo; cambiarla genera diffs enormes sin valor
- **SSR, framework o build step** — el sitio es estático por diseño

## Traceability

<!-- Completado por el roadmapper -->

| REQ-ID | Fase |
|---|---|
| SEC-01 | Phase 1 |
| SEC-02 | Phase 1 |
| SEC-03 | Phase 1 |
| INFRA-01 | Phase 1 |
| INFRA-02 | Phase 1 |
| INFRA-03 | Phase 1 |
| SEC-04 | Phase 2 |
| SEC-05 | Phase 2 |
| SEC-06 | Phase 2 |
| SEC-07 | Phase 2 |
| SEC-08 | Phase 2 |
| DATA-01 | Phase 3 |
| DATA-02 | Phase 3 |
| DATA-03 | Phase 3 |
| DATA-04 | Phase 3 |
| PORT-01 | Phase 4 |
| PORT-03 | Phase 4 |
| PORT-07 | Phase 4 |
| BRAND-01 | Phase 4 |
| BRAND-02 | Phase 4 |
| BRAND-03 | Phase 4 |
| PORT-02 | Phase 5 |
| PORT-04 | Phase 5 |
| PORT-05 | Phase 5 |
| PORT-06 | Phase 5 |
| PORT-08 | Phase 5 |
| BRAND-06 | Phase 5 |
| COT-01 | Phase 6 |
| COT-02 | Phase 6 |
| COT-03 | Phase 6 |
| BRAND-04 | Phase 7 |
| BRAND-05 | Phase 7 |
| FIX-01 | Phase 8 |
| FIX-02 | Phase 8 |
| FIX-03 | Phase 8 |
| FIX-04 | Phase 8 |
