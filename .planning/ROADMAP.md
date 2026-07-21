# Roadmap: Tierra Nativa — Sitio B2B Mayorista (v1: Port desde PaginaLK)

## Overview

Elias es un fork de PaginaLK que quedo a mitad de camino: la base de datos ya tiene paridad con LK, pero el frontend nunca se porto y arrastra deuda de seguridad critica (service_role key expuesta, 2FA comentado, updates masivos sin confirmacion). El viaje de este milestone va de "sitio inseguro y a medio portar" a "sitio Tierra Nativa completo, seguro y funcional de punta a punta": primero se cierra la deuda de seguridad y de base de datos que es independiente del port (para que los bugs no viajen al codigo nuevo), despues se reemplazan los archivos de frontend en bloque desde PaginaLK con la taxonomia y el branding de Tierra Nativa, y por ultimo se corrigen los bugs funcionales conocidos que el port reintroduce.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

- [ ] **Phase 1: Perimetro y Deuda Critica de Seguridad** - Identificar el webroot, sacar la service_role key del codigo, rotarla, y cerrar el acceso HTTP a scripts de mantenimiento
- [ ] **Phase 2: Endurecimiento del Panel Admin** - Reactivar 2FA, confirmar updates masivos, corregir XSS, PIN criptografico y privilegios reales (no solo CSS)
      **REORDENADA 2026-07-21: se ejecuta DESPUES de la Phase 5.** Ver "Nota de resecuenciamiento" abajo.
- [ ] **Phase 3: Limpieza y Endurecimiento de Base de Datos** - Resolver overloads de RPC duplicados, blindar reporting SECURITY DEFINER y eliminar migraciones obsoletas sin tocar fichaje_*
- [ ] **Phase 4: Port de Frontend — Catalogo y Checkout** - Reemplazar script.js/mayorista.html/index.html desde PaginaLK con taxonomia y credenciales de Tierra Nativa; compra de punta a punta funcional
- [ ] **Phase 5: Port de Frontend — Admin, Paginas Secundarias y Limpieza de Modulos Excluidos** - Portar admin.js/admin.html, historial y sugerencias; stripear OSA/TyL/bot/Chef/pedido automatico del repo
- [ ] **Phase 6: Cotizadores de Supermercados (rama LK)** - Portar los cotizadores contra el Supabase de Tierra Nativa, sin path a Chef, sin numeros de pedido fabricados
- [ ] **Phase 7: Branding Final y Contenido Institucional** - Logos, imagenes y textos 100% Tierra Nativa; sitemap y robots.txt reales
- [ ] **Phase 8: Correccion de Bugs Heredados Post-Port** - Doble submit, errores silenciados, borrado masivo de tracking y sucursal perdida en checkout

## Phase Details

### Phase 1: Perimetro y Deuda Critica de Seguridad
**Goal**: La service_role key deja de estar expuesta y el webroot queda identificado y cerrado a scripts de mantenimiento, antes de tocar una sola linea del port.
**Depends on**: Nothing (first phase)
**Requirements**: INFRA-01, INFRA-02, INFRA-03, SEC-01, SEC-02, SEC-03
**Success Criteria** (what must be TRUE):
  1. Se puede nombrar la carpeta exacta que sirve IIS como webroot y el mecanismo por el que se despliega, documentado.
  2. Ningun script de mantenimiento de storage contiene la `service_role` key en texto plano; se lee desde variable de entorno.
  3. La `service_role` key que estaba en el historial de git fue rotada en Supabase y ya no autentica.
  4. Pedir por HTTP cualquier script de mantenimiento (`storage-audit.js` y los otros 7) devuelve 403/404, no el codigo fuente.
  5. El estado del certificado HTTPS esta diagnosticado con una fuente externa (SSL Labs — no la PC del usuario, donde hay interceptacion TLS local que falsea el resultado). Si resulta invalido, queda registrado como pendiente accionable con los pasos de renovacion.
     *Nota de alcance:* INFRA-03 se cierra con diagnostico + remediacion documentada, NO con el certificado efectivamente renovado. La renovacion depende del hosting (GoDaddy) y puede exceder la fase. Desacoplado a proposito para que no bloquee el cierre de SEC-01/02/03 e INFRA-01/02, que son la deuda critica real. Si al terminar la fase el certificado sigue invalido, INFRA-03 vuelve al backlog, no se marca cumplido.
**Plans**: 5 plans en 3 waves

Plans:
- [ ] 01-01-PLAN.md — SEC-01: sacar la service_role key de los 8 scripts a variable de entorno (Claude, autonomo)
- [ ] 01-02-PLAN.md — INFRA-01: identificar webroot y mecanismo de deploy (USUARIO + Claude documenta)
- [ ] 01-03-PLAN.md — SEC-02: rotar la key en el dashboard de Supabase (USUARIO + Claude verifica y registra)
- [ ] 01-04-PLAN.md — INFRA-02: reglas de deny en web.config y despliegue al webroot (Claude escribe + USUARIO despliega)
- [ ] 01-05-PLAN.md — SEC-03 + INFRA-03: verificacion externa por HTTP y estado real del certificado TLS (USUARIO verifica + Claude registra)

**Waves:** W1 = {01, 02} · W2 = {03 (dep 01), 04 (dep 02)} · W3 = {05 (dep 03, 04)}
**Nota de secuenciamiento:** el Plan 01 (sacar la key del codigo) va SI o SI antes del Plan 03 (rotar). Rotar primero deja los 8 scripts rotos sin aviso.

### Phase 2: Endurecimiento del Panel Admin
**Goal**: El panel admin deja de ser vulnerable a los vectores criticos/altos de la auditoria: sin 2FA, updates masivos sin confirmar, XSS y PIN predecible.
**Depends on**: **Phase 5** (resecuenciada — ver nota abajo). Ejecutar antes de la Phase 5 es trabajo tirado.

> **Nota de resecuenciamiento (2026-07-21, durante la ejecucion de la Phase 1).**
>
> El roadmap original ponia esta fase en segundo lugar, por la decision explicita de "seguridad primero".
> Al ejecutar la Phase 1 se verifico el `admin.js` de PaginaLK y se descubrio que **comparte 3 de los 4
> bugs**, con lo cual la Phase 5 (que reemplaza `admin.js` completo) los reintroduce:
>
> | Req | Estado en `PaginaLK/admin.js` | Consecuencia |
> |---|---|---|
> | SEC-04 (2FA) | **ACTIVO**, no comentado (`admin.js:58-60`) | El port lo arregla solo. Hacerlo a mano ahora es trabajo doble |
> | SEC-05 (UPDATE masivos) | Mismo bug, y ademas una 4ta instancia (`5867`, `6037`, `6213`, `6374`) | El fix tiene que ir sobre el codigo portado |
> | SEC-06 (XSS en grilla) | Mismo bug (`renderClientes`, `1171-1211`) | Idem |
> | SEC-07 (PIN `Math.random()`) | Mismo bug (`374-375`) | Idem |
>
> Es el mismo razonamiento por el que los FIX-01..04 ya estaban pospuestos a la Phase 8: son bugs de
> PaginaLK que el port reintroduce. La diferencia es que al armar el roadmap no se habia verificado
> que LK compartiera tambien los de seguridad.
>
> **Esto NO abandona "seguridad primero".** La deuda verdaderamente critica e independiente del port
> —la `service_role` key expuesta— es la Phase 1 y sigue primero. Los 8 scripts de mantenimiento no
> forman parte del port, asi que ese trabajo no se pisa.
>
> **Riesgo aceptado:** el XSS y los UPDATE masivos siguen vivos en produccion hasta despues de la
> Phase 5. Se acepta porque el sitio tiene 1 solo pedido y practicamente cero uso, y porque el unico
> vector del XSS es un admin cargando un Excel malicioso a si mismo.
>
> **Como revertir:** si se prefiere blindar produccion ya mismo aun a costa de hacer el trabajo dos
> veces, mover esta fase de nuevo al segundo lugar. La decision es reversible; el trabajo duplicado no.
>
> **Orden de ejecucion resultante:** 1 → 3 → 4 → 5 → 2 → 6 → 7 → 8
**Requirements**: SEC-04, SEC-05, SEC-06, SEC-07, SEC-08
**Success Criteria** (what must be TRUE):
  1. Loguearse como admin PPP sin completar el segundo factor no otorga acceso al panel.
  2. Subir un Excel de deuda, limite de credito o plazo de pago pide confirmacion explicita antes de escribir, y si el parseo produce cero filas no toca la cartera.
  3. Cargar un cliente con `business_name` conteniendo un `<script>` no ejecuta codigo al abrir la grilla de clientes.
  4. Un PIN de cliente recien generado usa `crypto.getRandomValues()`, no `Math.random()`.
  5. Un admin comun no puede ejecutar acciones reservadas a PPP aunque revele con DOM/CSS los controles ocultos.
**Plans**: TBD
**UI hint**: yes

### Phase 3: Limpieza y Endurecimiento de Base de Datos
**Goal**: Los RPCs que el frontend portado va a consumir responden sin ambiguedad y sin exponer reporting a no-admins; el repo deja de arrastrar migraciones muertas, sin tocar fichaje_*.
**Depends on**: Nothing tecnico; se secuencia junto a Phases 1-2 por ser deuda pre-port independiente del frontend
**Requirements**: DATA-01, DATA-02, DATA-03, DATA-04
**Success Criteria** (what must be TRUE):
  1. Llamar a `get_my_linked_customers` y `get_products_public_sorted` no devuelve error `function is not unique`.
  2. Un usuario no-admin que invoca las RPC `SECURITY DEFINER` de reporting recibe rechazo, no datos.
  3. El repo ya no contiene ningun `migration_tn*.sql`.
  4. Despues de estos cambios, las 6 tablas y los 37 RPCs de `fichaje_*` siguen respondiendo igual que antes (DATA-04, verificacion transversal obligatoria de esta fase).
**Plans**: 6 plans en 5 waves

Plans:
- [ ] 03-01-PLAN.md — Baseline forense: definiciones, GRANTs y snapshot de fichaje_* antes de tocar nada (Claude, autonomo, MCP read-only)
- [ ] 03-02-PLAN.md — DATA-03: borrar los 4 migration_tn*.sql (Claude, autonomo, no toca la base)
- [ ] 03-03-PLAN.md — Autoria del SQL de DATA-01 y DATA-02 + rollback; checkpoint para habilitar escritura en el MCP (Claude escribe + USUARIO decide via)
- [ ] 03-04-PLAN.md — DATA-01: aplicar y probar el drop de overloads (Claude, MCP con escritura)
- [ ] 03-05-PLAN.md — DATA-02: aplicar guards y probar rechazo + no-regresion (Claude, MCP con escritura)
- [ ] 03-06-PLAN.md — DATA-04: diff antes/despues de fichaje_* + restaurar --read-only (Claude verifica + USUARIO restaura)

**Waves:** W1 = {01, 02} · W2 = {03 (dep 01, 02)} · W3 = {04 (dep 03)} · W4 = {05 (dep 04)} · W5 = {06 (dep 04, 05)}

**Nota de secuenciamiento:** el Plan 01 va SI o SI antes del 04 y del 05. Sin el baseline forense
(`pg_get_functiondef` de cada funcion antes de modificarla) un DROP contra produccion no tiene
vuelta atras. Los Planes 04 y 05 son secuenciales entre si a proposito: son los dos unicos DDL de
la fase contra una base con 541 clientes y sin staging, y serializarlos permite atribuir cualquier
rotura a un cambio concreto.

**Correcciones al enunciado original de la fase, halladas al planificar** (detalle en 03-03-PLAN.md):

1. **DATA-01 no usa el mismo criterio en los dos pares.** En `get_my_linked_customers` sobrevive
   el overload sin argumentos (usa `auth.uid()`, es el seguro y el que llaman los 3 call sites de
   PaginaLK). En `get_products_public_sorted` sobrevive el de `(sort_mode text)`: ambos frontends
   —`script.js:772` en Elias y `script.js:1023` en LK— pasan `sort_mode`. Dropear el `(text)`
   romperia el catalogo en los dos.

2. **DATA-02 no son 7 chequeos de admin, son 5 + 2.** `get_my_assortment_18m` la llama
   `script.js:1631`, un **cliente mayorista**, no un admin: ponerle guard de admin deja sin
   catalogo a los 541 clientes. Junto con `get_customer_sales_history` lleva guard de
   dueño-o-admin. Las otras 5 si son admin puro.

3. **Riesgo de GRANT no previsto.** `script.js:772` llama al catalogo en contexto `anon`. Si en
   produccion `get_products_public_sorted(text)` no tiene GRANT a `anon` (los archivos muertos
   sugieren que solo lo tenia el overload sin argumentos), dropear el `()` vacia el catalogo
   publico. El Plan 01 lo verifica y el Plan 04 grantea **antes** de dropear.

### Phase 4: Port de Frontend — Catalogo y Checkout
**Goal**: Un cliente mayorista puede loguearse, navegar el catalogo de Tierra Nativa con su taxonomia real, armar un carrito y confirmar un pedido de punta a punta sobre el codigo portado desde PaginaLK.
**Depends on**: Phase 1, Phase 3 (necesita el perimetro cerrado y los RPC sin ambiguedad)
**Requirements**: PORT-01, PORT-03, PORT-07, BRAND-01, BRAND-02, BRAND-03
**Success Criteria** (what must be TRUE):
  1. El catalogo carga los 336 productos de Tierra Nativa usando `script.js`/`mayorista.html`/`css/styles.css` portados desde PaginaLK.
  2. El menu de categorias muestra Cuadros / Deco / Portaretratos / Importados en ese orden, con las subcategorias colgando de Cuadros (no de Utensilios).
  3. `index.html` (landing) esta portado desde PaginaLK y no apunta a credenciales de Loekemeyer.
  4. Un cliente puede loguearse por CUIT+PIN, agregar productos al carrito y confirmar un pedido de punta a punta sin error.
  5. Toda declaracion de `SUPABASE_URL`/anon key en el frontend apunta al proyecto de Tierra Nativa (`zjvpzqhbekxnwxdczpof`), ninguna a Loekemeyer.
**Plans**: TBD
**UI hint**: yes

### Phase 5: Port de Frontend — Admin, Paginas Secundarias y Limpieza de Modulos Excluidos
**Goal**: El panel admin y las paginas secundarias (historial, sugerencias) quedan portados y funcionales, y el repo deja de arrastrar codigo de los modulos que Tierra Nativa no usa.
**Depends on**: Phase 4 (mismo bloque de copiado masivo de archivos, separado para acotar el radio de verificacion)
**Requirements**: PORT-02, PORT-04, PORT-05, PORT-06, PORT-08, BRAND-06
**Success Criteria** (what must be TRUE):
  1. `admin.html`/`admin.js`/`css/admin.css` abren sin errores de consola, y ninguno de los 6 scripts que `admin.html` referencia (`version.js`, `excel-parser-smart.js`, `argentina-map-data.js`, `analisis-venta-cliente.js`, entre otros) da 404.
  2. `historial.html`/`historial.js` muestran el historial de compras de un cliente sin error.
  3. `sugerencias.html` existe y trae datos reales desde las RPC `sugerencias_cliente` y `novedades_marca`.
  4. Buscar en el repo cualquier archivo o referencia a OSA, TyL, bot de WhatsApp, Chef o pedido automatico no encuentra resultados.
  5. `historial`, `sugerencias` y `admin` llevan `noindex` en su `<head>`.
**Plans**: TBD
**UI hint**: yes

### Phase 6: Cotizadores de Supermercados (rama LK)
**Goal**: Los cotizadores de supermercados funcionan desde el panel ya portado, contra el Supabase de Tierra Nativa, sin path a Chef y sin fabricar pedidos falsos ante un fallo.
**Depends on**: Phase 5 (los cotizadores cuelgan de `admin.html`, ya portado)
**Requirements**: COT-01, COT-02, COT-03
**Success Criteria** (what must be TRUE):
  1. `admin-supercot.js` y `admin-excel-krikos.js` estan presentes y operan desde el panel admin portado.
  2. Ningun request de los cotizadores apunta al proyecto Supabase de Chef; todos resuelven contra el de Tierra Nativa.
  3. Si el RPC de submit falla, el flujo se corta y muestra error — no aparece un numero de pedido inventado.
**Plans**: TBD
**UI hint**: yes

### Phase 7: Branding Final y Contenido Institucional
**Goal**: No queda rastro de Loekemeyer en el contenido publico y el sitio es indexable/no-indexable donde corresponde.
**Depends on**: Phase 5 (necesita el listado final de paginas publicas para armar el sitemap)
**Requirements**: BRAND-04, BRAND-05
**Success Criteria** (what must be TRUE):
  1. Ningun logo, imagen, video o texto institucional del sitio publico menciona o muestra a Loekemeyer.
  2. `sitemap.xml` declara `https://` y las URLs publicas reales de Tierra Nativa, y existe un `robots.txt` en el webroot.
**Plans**: TBD

### Phase 8: Correccion de Bugs Heredados Post-Port
**Goal**: Los bugs funcionales conocidos de PaginaLK, que el port reintroduce, quedan corregidos en el codigo final ya estable.
**Depends on**: Phase 4, Phase 5, Phase 6 (todo el codigo relevante ya portado)
**Requirements**: FIX-01, FIX-02, FIX-03, FIX-04
**Success Criteria** (what must be TRUE):
  1. Un doble click en "Confirmar pedido" no genera pedidos duplicados.
  2. Un error de Supabase al borrar o editar una sucursal se muestra al admin, no un toast de exito falso.
  3. El borrado masivo de tracking verifica el resultado antes de insertar la tanda nueva.
  4. Cambiar de pestana o volver del historial no borra la sucursal ya elegida en el checkout.
**Plans**: TBD
**UI hint**: yes

## Progress

**Execution Order:**
**1 → 3 → 4 → 5 → 2 → 6 → 7 → 8**

Ya NO es orden numerico. La Phase 2 se movio despues de la Phase 5 el 2026-07-21: se verifico que
`PaginaLK/admin.js` comparte 3 de los 4 bugs de seguridad que la fase corrige, con lo cual el port
los reintroduce y el trabajo se haria dos veces. Detalle completo en la nota de la Phase 2.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Perimetro y Deuda Critica de Seguridad | 0/5 | Planned | - |
| 2. Endurecimiento del Panel Admin | 0/TBD | Not started | - |
| 3. Limpieza y Endurecimiento de Base de Datos | 0/6 | Planned | - |
| 4. Port de Frontend — Catalogo y Checkout | 0/TBD | Not started | - |
| 5. Port de Frontend — Admin, Paginas Secundarias y Limpieza de Modulos Excluidos | 0/TBD | Not started | - |
| 6. Cotizadores de Supermercados (rama LK) | 0/TBD | Not started | - |
| 7. Branding Final y Contenido Institucional | 0/TBD | Not started | - |
| 8. Correccion de Bugs Heredados Post-Port | 0/TBD | Not started | - |
