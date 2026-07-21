# Patch para ROADMAP.md — Phase 3

Reemplazar la linea 100 de `.planning/ROADMAP.md` (`**Plans**: TBD`) por el bloque de abajo,
y actualizar la fila de la Phase 3 en la tabla de Progress a `0/6 | Planned`.

---

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
