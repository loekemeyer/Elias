# Tierra Nativa — Sitio B2B Mayorista

## What This Is

Sitio web mayorista (B2B) de Tierra Nativa SA, fabricante argentino de cuadros, portarretratos y objetos de decoración, publicado en `tierravintage.com.ar`. Los clientes mayoristas entran con su CUIT, navegan el catálogo con sus precios y condiciones, arman un pedido y lo confirman; un panel admin gestiona clientes, sucursales, precios, condiciones comerciales y el seguimiento de entregas.

Técnicamente es un sitio estático (HTML + JS, sin build step) servido por IIS, donde todo el JavaScript corre en el browser y habla directo con Supabase. Es un fork de PaginaLK — el mismo sistema construido para Loekemeyer SRL — que quedó a mitad de camino.

## Core Value

Que un cliente mayorista pueda entrar, ver sus precios reales y dejar un pedido confirmado sin llamar por teléfono.

## Requirements

### Validated

<!-- Ya existe y funciona en el fork actual. -->

- ✓ Login de clientes por CUIT con PIN de 6 dígitos contra Supabase Auth — existente
- ✓ Catálogo de productos con imágenes desde Supabase Storage — existente
- ✓ Carrito y confirmación de pedido vía RPC `submit_order_fast` — existente
- ✓ Panel admin con alta/edición de clientes y sucursales — existente
- ✓ Importación de clientes por Excel — existente
- ✓ Historial de compras por cliente — existente
- ✓ Base de datos ya migrada a paridad con PaginaLK (2026-07-03) — existente

### Active

<!-- Objetivo de este milestone. -->

- [ ] Rotar la `service_role` key expuesta y sacar los scripts de mantenimiento del webroot
- [ ] Determinar dónde está realmente el webroot y cómo se despliega
- [ ] Reactivar el 2FA de admin, hoy comentado en producción
- [ ] Poner confirmación en los tres UPDATE masivos sobre toda la cartera de clientes
- [ ] Corregir el XSS almacenado en la grilla de clientes del panel
- [ ] Corregir los errores de Supabase silenciados que muestran toast de éxito ante fallo
- [ ] Reemplazar la generación de PIN con `Math.random()` por `crypto.getRandomValues()`
- [ ] Portar el frontend completo desde PaginaLK (`script.js` 117KB → 369KB)
- [ ] Adaptar `CATEGORY_ORDER` a la taxonomía de Tierra Nativa (Cuadros / Deco / Portaretratos / Importados)
- [ ] Adaptar el orden de subcategorías: en LK cuelgan de Utensilios, acá cuelgan de Cuadros
- [ ] Reapuntar credenciales, branding, dominio, `sitemap.xml` y `robots.txt` a Tierra Nativa
- [ ] Portar los cotizadores de supermercados usando solo la rama LK
- [ ] Dropear los dos overloads duplicados de RPC (`get_my_linked_customers`, `get_products_public_sorted`)
- [ ] Eliminar los `migration_tn*.sql` obsoletos del repo
- [ ] Corregir el doble submit de pedido en `script.js`

### Out of Scope

- **Módulo OSA** — vertical de Loekemeyer, Tierra Nativa no lo usa
- **Módulo Torres y Liva (tyl)** — ídem, cliente específico de LK
- **Bot de WhatsApp (`bot_*`, `Wpp_*`)** — ~20 tablas, decisión explícita de no portarlo
- **Integración Chef (`ventas_chef`, `chef_*`)** — los precios de Tierra Nativa salen de su propio Supabase, no de Chef
- **Pedido automático (`pa_*`)** — vertical de LK, no aplica
- **Módulo `fichaje_*`** — es exclusivo de Elias y NO se toca: 6 tablas, 30+ RPCs, 17 migraciones, con frontend fuera de este repo
- **Modernizar `admin.js` a sintaxis moderna** — usa `var` y funciones de forma consistente; cambiarlo por gusto genera diffs enormes sin valor
- **SSR o framework** — el sitio es estático por diseño, sin build step

## Context

**Origen del proyecto.** Elias es un fork de PaginaLK (Loekemeyer SRL, Supabase `kwkclwhmoygunqmlegrg`), adaptado para Tierra Nativa SA (Supabase `zjvpzqhbekxnwxdczpof`). El 2026-07-03 alguien migró la base de datos de Elias a paridad con LK — migraciones `paridad_paginalk_tablas_y_rpcs`, `paridad_paginalk_admin_orders_y_vistas`, `paridad_rpcs_login_username_y_vendor_pdf` — y después el proyecto se desvió al módulo de fichaje. **El frontend quedó sin portar.**

**Consecuencia clave:** la base ya tiene los 13 RPCs que el `script.js` de PaginaLK necesita (`submit_order_fast`, `edit_order_fast`, `get_my_assortment_18m`, `get_my_linked_customers`, `has_loke_access`, `get_customer_sales_history`, `sugerencias_cliente`, `novedades_marca`, `get_products_public_sorted`, `lookup_cuit_by_username`, `vendor_get_order_full`, `get_my_vendor_orders`, `get_my_group_customers`). El port es casi todo trabajo de frontend, no de base de datos.

**Estado de los datos (verificado 2026-07-21):**

| Tabla | Filas |
|---|---|
| `customers` | 541 |
| `auth.users` | 539 |
| `products` | 336 (286 activos, todos con imagen) |
| `orders` / `order_items` | 1 / 1 |
| `admins` | 1 |
| `sales_lines` | 0 |

El sitio está publicado pero sin uso real: 541 clientes tienen cuenta creada y hay un solo pedido.

**Catálogo:**

| Categoría | Productos | Con subcategoría |
|---|---|---|
| Cuadros | 173 | 155 |
| Deco | 93 | 0 |
| Portaretratos | 65 | 0 |
| Importados | 5 | 0 |

Subcategorías de Cuadros: Abstracto, Beach, Bauhaus, Arpillera, Artemisa, Animales ByN, Black & White, entre otras.

**Deuda técnica heredada (auditoría 2026-07-21).** Crítico: `service_role` key hardcodeada en 8 scripts de mantenimiento de storage que viven en la misma carpeta que el sitio, y `web.config` no tiene ninguna regla que los bloquee; 2FA de admin comentado en producción (`admin.js:58-62`); tres UPDATE masivos sobre toda la cartera sin confirmación (`admin.js:5328`, `5498`, `5674`). Alto: XSS almacenado en la grilla de clientes (`admin.js:1086`); errores de Supabase ignorados con toast de éxito (`admin.js:2291`, `996`, `1200`); doble submit de pedido (`script.js:2687`); PIN de clientes generado con `Math.random()` (`admin.js:331`).

**Incógnita abierta.** No está identificado dónde vive el webroot ni cómo se despliega. `tierravintage.com.ar` resuelve a 107.180.4.212 (GoDaddy). Desde esta PC la validación TLS falla, pero el issuer del certificado delata interceptación local, así que no es concluyente. Pendiente: abrir `https://tierravintage.com.ar/storage-audit.js` en un navegador — si devuelve código, la key está pública.

**Referencia.** El código fuente de PaginaLK está en `Y:\AA IT\Elias-main\PaginaLK-main\PaginaLK-main` y su `CLAUDE.md` documenta convenciones que aplican también acá.

## Constraints

- **Tech stack**: HTML + JS plano, sin build step ni bundler, servido por IIS — el sitio es el deliverable, los archivos se copian tal cual
- **Backend**: Supabase accedido directo desde el browser con la anon key; la seguridad real vive en RLS y en las RPC `SECURITY DEFINER`
- **Datos**: 541 clientes y 539 cuentas de auth en producción — ninguna migración puede tocar `customers` ni `auth.users` sin backup previo
- **Compatibilidad**: el módulo `fichaje_*` tiene frontend fuera de este repo; sus 30+ RPCs no se pueden romper
- **Idioma**: todo el código, UI, variables y comentarios están en español — mantener el estilo
- **Concurrencia**: el repo vive en un share de red SMB con varias personas editando; aplica el protocolo de locks de `.locks/active.json` documentado en el `CLAUDE.md` de PaginaLK
- **Seguridad**: el repo git contiene la `service_role` key en su historial — NO publicar en ningún remoto hasta rotarla

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Reemplazo total de archivos desde LK en vez de port selectivo | Elias está tan atrasado que un port feature-by-feature dejaría un híbrido difícil de mantener y el drift volvería | — Pending |
| Seguridad antes que port | Los bugs críticos son independientes del port; arreglarlos primero evita que viajen al código nuevo | — Pending |
| Cotizadores de supermercados sí, pero solo la rama LK | Tierra Nativa tiene sus precios en su propio Supabase; el path a Chef no aplica | — Pending |
| No portar bot de WhatsApp, Chef, OSA, TyL ni pedido automático | Son verticales de Loekemeyer sin uso en Tierra Nativa; portarlos sería arrastrar ~30 tablas muertas | — Pending |
| `.planning/` versionado dentro del repo | Es memoria del proyecto y debe viajar con el código | — Pending |
| git init con backup en frío previo | No había control de versiones y el alcance es un reemplazo masivo de archivos | ✓ Good |
| Modo YOLO con los tres agentes de verificación activos | Velocidad en la aprobación, pero sin resignar el control de calidad, que es la única red sin tests automáticos | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-07-21 after initialization*
