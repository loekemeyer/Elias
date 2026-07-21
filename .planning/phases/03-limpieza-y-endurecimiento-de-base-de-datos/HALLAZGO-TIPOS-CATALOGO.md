---
severity: BLOQUEANTE de la Phase 4
afecta: DATA-01, BRAND-03, PORT-01, PORT-07
descubierto: 2026-07-21, ejecutando el baseline del Plan 03-01
---

# Los dos overloads del catalogo devuelven formas distintas, y ninguna sirve tal cual

## El problema en una linea

`get_products_public_sorted(text)` —el overload que el plan decide conservar— devuelve
`subcategory` como el string literal **`{Beach}`**, con llaves incluidas.

## Como se llego

El Plan 03-04 iba a dropear `get_products_public_sorted()` y conservar `(text)`, porque ambos
frontends la invocan pasando `sort_mode`. El razonamiento es correcto en cuanto a la firma. Pero
al capturar las definiciones textuales aparecio un desajuste de tipos que nadie habia mirado.

| Columna | Tabla `products` | overload `()` | overload `(text)` |
|---|---|---|---|
| `subcategory` | `text[]` | `text[]` ✅ | **`text`** ❌ |
| `images` | `jsonb` | `jsonb` ✅ | **`text`** ❌ |
| `ranking` | `integer` | `integer` | `numeric` |
| `orden_catalogo` | `integer` | `integer` | `numeric` |
| `list_price` | `numeric` | presente | **ausente** |
| `active` | `boolean` | presente | **ausente** |

El overload `(text)` no falla: Postgres aplica cast de asignacion `text[] -> text` y
`jsonb -> text`. Devuelve 286 filas correctamente. Pero el contenido sale serializado.

Verificado contra produccion:

```sql
select cod, subcategory, pg_typeof(subcategory)
from get_products_public_sorted('ranking'::text)
where category = 'Cuadros' limit 1;
```
```
cod=084  subcategory={Beach}  pg_typeof=text
```

## Por que rompe el port

`PaginaLK/script.js:1126-1127` y `:3535` hacen:

```js
p.subcategory && String(p.subcategory).trim()
  ? String(p.subcategory).trim()
  : ...
```

El frontend de LK trata `subcategory` como **string plano**. Con los datos de Tierra Nativa eso
produce `"{Beach}"` — con llaves — que es lo que terminaria mostrandose en el menu de
subcategorias y usandose como clave de filtrado.

Consecuencias concretas despues del port:

1. El menu de subcategorias de Cuadros muestra `{Beach}`, `{Bauhaus}`, `{Abstracto}`...
2. Los productos con mas de una subcategoria colapsan en una sola clave: `{Beach,Marino}` pasa a
   ser una subcategoria propia, distinta de `{Beach}`.
3. El filtrado por subcategoria queda inconsistente con cualquier UI que ofrezca las
   subcategorias por separado.

Afecta a **155 de los 173 productos de Cuadros**, que es la categoria principal del catalogo.

## Por que esto no se habia detectado

- El roadmap trata BRAND-03 como "cambiar el orden de subcategorias, que en LK cuelgan de
  Utensilios y aca de Cuadros". Es un problema de **modelo de datos**, no de orden.
- La planificacion de la Phase 3 comparo las firmas y los call sites, que es lo correcto para
  DATA-01, pero no los tipos de retorno contra el esquema de la tabla.
- El `script.js` actual de Elias tambien llama a `get_products_public_sorted` con `sort_mode`
  (`script.js:772`), asi que **el bug ya existe hoy en produccion**. No lo introduce el port.
  Simplemente hoy casi nadie usa el sitio, asi que nadie lo reporto.

## Opciones

**A — Arreglar el overload que sobrevive (recomendada).**
Redefinir `get_products_public_sorted(sort_mode text)` para que devuelva `subcategory text[]` e
`images jsonb`, agregando ademas `list_price` y `active`, que hoy no devuelve. Despues adaptar el
frontend portado para que maneje el array. Deja la base coherente consigo misma y no arrastra el
problema.

**B — Aplanar en la funcion.**
Que la RPC devuelva `array_to_string(p.subcategory, ', ')` en vez del cast crudo. El frontend de LK
sigue funcionando sin tocarlo, y no aparecen llaves. Es la opcion de menor cambio, pero pierde la
capacidad de filtrar por subcategoria individual cuando un producto tiene varias.

**C — Conservar el overload `()` en lugar del `(text)`.**
Devuelve los tipos correctos, pero ningun frontend lo llama sin argumentos y perderia el
`sort_mode`. Habria que tocar los dos frontends. No la recomiendo.

## Decision requerida antes del Plan 03-04

El Plan 03-04 no deberia dropear nada hasta que esto se resuelva: si dropea el overload `()`, se
pierde la unica version que devuelve los tipos correctos, y la opcion A pasa a tener que
reconstruirlos desde este baseline en vez de simplemente conservarlos.

**Recomendacion: opcion A, y mover la redefinicion de tipos al Plan 03-04**, que ya va a estar
tocando esa funcion con el MCP en modo escritura. Es el mismo DDL, una sola vez.
