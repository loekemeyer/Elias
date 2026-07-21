-- =====================================================================
-- Phase 3 — DDL de DATA-01 y DATA-02 + correccion de tipos del catalogo
-- Proyecto: zjvpzqhbekxnwxdczpof (Tierra Nativa) — PRODUCCION
-- Autoria: 2026-07-21
--
-- ROLLBACK: baseline/funciones-antes.sql restaura el estado previo exacto.
-- Verificar que ese archivo este commiteado ANTES de correr esto.
--
-- Correr como UNA sola transaccion. Si algo falla, no debe quedar a medias:
-- hay una ventana en la que el catalogo no existe (entre el DROP y el
-- CREATE del bloque 2) y con 541 clientes en produccion eso no puede
-- quedar colgado.
-- =====================================================================

BEGIN;

-- =====================================================================
-- BLOQUE 1 — DATA-01: get_my_linked_customers
-- =====================================================================
-- Sobrevive: ()          usa auth.uid(), es el seguro
-- Se dropea: (uuid)      recibe el uuid por parametro -> pasando otro
--                        uuid se ve la cartera ajena. Vulnerabilidad real,
--                        no solo un duplicado.
--
-- Call sites verificados en PaginaLK: historial.js:354, script.js:8183,
-- sugerencias.js:237 — los tres SIN argumentos. Coinciden con el que queda.

DROP FUNCTION IF EXISTS public.get_my_linked_customers(uuid);


-- =====================================================================
-- BLOQUE 2 — DATA-01 + correccion de tipos: get_products_public_sorted
-- =====================================================================
-- Sobrevive la firma (sort_mode text): ambos frontends la llaman asi
--   (Elias script.js:772, PaginaLK script.js:1023).
--
-- PERO se redefine el cuerpo. La version actual declara subcategory text
-- e images text mientras la tabla los tiene como text[] y jsonb, con lo
-- cual Postgres castea y subcategory sale como el string '{Beach}' —
-- con llaves. Afecta a 155 de los 173 productos de Cuadros.
--
-- Cambios respecto de la version actual:
--   subcategory   text     -> text[]     (coincide con la tabla)
--   images        text     -> jsonb      (coincide con la tabla)
--   ranking       numeric  -> integer    (coincide con la tabla)
--   orden_catalogo numeric -> integer    (coincide con la tabla)
--   + list_price  numeric  (faltaba; el overload () si lo devolvia)
--   + active      boolean  (faltaba; idem)
--
-- Cambiar el tipo de retorno obliga a DROP + CREATE: CREATE OR REPLACE
-- no admite cambiar las columnas de un RETURNS TABLE.

DROP FUNCTION IF EXISTS public.get_products_public_sorted();
DROP FUNCTION IF EXISTS public.get_products_public_sorted(text);

CREATE FUNCTION public.get_products_public_sorted(sort_mode text DEFAULT 'ranking'::text)
 RETURNS TABLE(
   id uuid,
   cod text,
   category text,
   subcategory text[],
   description text,
   list_price numeric,
   uxb integer,
   active boolean,
   images jsonb,
   orden_catalogo integer,
   ranking integer,
   badge_status text
 )
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT p.id, p.cod, p.category, p.subcategory,
         p.description, p.list_price, p.uxb, p.active,
         p.images, p.orden_catalogo, p.ranking, p.badge_status
  FROM products p
  WHERE p.active = true
  ORDER BY
    CASE WHEN sort_mode = 'catalogo' THEN p.orden_catalogo ELSE p.ranking END NULLS LAST,
    p.description;
$function$;

-- Los GRANT se pierden con el DROP. Restaurarlos EXACTAMENTE como estaban
-- (ver baseline/grants-antes.txt): anon incluido, el catalogo es publico.
GRANT EXECUTE ON FUNCTION public.get_products_public_sorted(text) TO anon;
GRANT EXECUTE ON FUNCTION public.get_products_public_sorted(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_products_public_sorted(text) TO service_role;


-- =====================================================================
-- BLOQUE 3 — DATA-02: guards de admin puro (5 funciones)
-- =====================================================================
-- Patron: se copia el de get_all_sales_lines_admin_with_customer, que ya
-- valida correctamente. Guard via EXISTS en el WHERE, no RAISE: estas
-- funciones son LANGUAGE sql y sql no puede hacer RAISE EXCEPTION.
-- Convertirlas a plpgsql seria un cambio mas grande sin beneficio: un
-- no-admin recibe cero filas, que es rechazo efectivo.
--
-- Se usa CREATE OR REPLACE: la firma y el tipo de retorno no cambian,
-- solo el cuerpo. Los GRANT se conservan.

-- --- 3.1 get_all_sales_lines_admin() -------------------------------
CREATE OR REPLACE FUNCTION public.get_all_sales_lines_admin()
 RETURNS TABLE(item_code text, ym text, boxes bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH raw AS (
    SELECT
      sl.item_code::text AS item_code,
      CASE
        WHEN sl.invoice_date::text ~ '^\d{4}-\d{2}-\d{2}'
          THEN substr(sl.invoice_date::text, 1, 7)
        WHEN sl.invoice_date::text ~ '^\d{1,2}/\d{1,2}/\d{4}$'
          THEN substr(sl.invoice_date::text, length(sl.invoice_date::text) - 3, 4)
            || '-'
            || lpad(split_part(sl.invoice_date::text, '/', 2), 2, '0')
        ELSE NULL
      END AS ym,
      sl.boxes::bigint AS boxes
    FROM public.sales_lines sl
    WHERE sl.invoice_date IS NOT NULL
      AND sl.item_code IS NOT NULL
      AND EXISTS (SELECT 1 FROM public.admins a WHERE a.auth_user_id = auth.uid())
  )
  SELECT item_code, ym, sum(boxes) AS boxes
  FROM raw
  WHERE ym IS NOT NULL
  GROUP BY item_code, ym;
$function$;

-- --- 3.2 get_estadistica_clientes_agg() ----------------------------
CREATE OR REPLACE FUNCTION public.get_estadistica_clientes_agg()
 RETURNS TABLE(cod_cliente text, last_purchase_date date, purchase_count integer, avg_interval_days numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH guard AS (
    SELECT EXISTS (SELECT 1 FROM admins a WHERE a.auth_user_id = auth.uid()) AS ok
  ),
  all_dates AS (
    SELECT c.cod_cliente::text, o.created_at::date AS purchase_date
    FROM orders o JOIN customers c ON c.id = o.customer_id
    WHERE c.cod_cliente IS NOT NULL AND (SELECT ok FROM guard)
    UNION
    SELECT sl.customer_code::text, to_date(substr(sl.invoice_date::text, 1, 10), 'YYYY-MM-DD')
    FROM sales_lines sl
    WHERE sl.customer_code IS NOT NULL
      AND sl.invoice_date::text ~ '^\d{4}-\d{2}-\d{2}'
      AND (SELECT ok FROM guard)
  ),
  with_lag AS (
    SELECT cod_cliente, purchase_date,
           LAG(purchase_date) OVER (PARTITION BY cod_cliente ORDER BY purchase_date) AS prev_date
    FROM all_dates
  )
  SELECT cod_cliente, MAX(purchase_date), COUNT(*)::int,
    ROUND(AVG(CASE WHEN (purchase_date - prev_date) > 0 AND (purchase_date - prev_date) < 730
                   THEN (purchase_date - prev_date)::numeric ELSE NULL END), 0)
  FROM with_lag GROUP BY cod_cliente;
$function$;

-- --- 3.3 get_estadistica_madre_detail(text,text) -------------------
CREATE OR REPLACE FUNCTION public.get_estadistica_madre_detail(p_item_code text, p_ym text)
 RETURNS TABLE(cod_cliente text, business_name text, provincia text, boxes bigint, unidades bigint, avg_monthly_units numeric, ratio numeric, via text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH guard AS (
    SELECT EXISTS (SELECT 1 FROM admins a WHERE a.auth_user_id = auth.uid()) AS ok
  ),
  item_uxb AS (
    SELECT coalesce(uxb,1)::numeric AS uxb FROM products WHERE cod::text = p_item_code LIMIT 1
  ),
  this_month AS (
    SELECT sl.customer_code::text AS cod_cliente, sum(sl.boxes)::bigint AS boxes
    FROM sales_lines sl
    WHERE sl.item_code::text = p_item_code AND substr(sl.invoice_date::text,1,7) = p_ym
      AND sl.customer_code IS NOT NULL
      AND (SELECT ok FROM guard)
    GROUP BY sl.customer_code
  ),
  historical AS (
    SELECT sl.customer_code::text AS cod_cliente,
           sum(sl.boxes)::numeric / nullif(count(distinct substr(sl.invoice_date::text,1,7)),0) AS avg_monthly_boxes
    FROM sales_lines sl
    WHERE sl.item_code::text = p_item_code AND substr(sl.invoice_date::text,1,7) < p_ym
      AND sl.customer_code IS NOT NULL
    GROUP BY sl.customer_code
  )
  SELECT tm.cod_cliente,
         coalesce(c.business_name,'—'),
         coalesce(c.localidad, 'Sin localidad'),
         tm.boxes,
         (tm.boxes * (SELECT uxb FROM item_uxb))::bigint,
         round(coalesce(h.avg_monthly_boxes,0) * (SELECT uxb FROM item_uxb), 0),
         CASE WHEN h.avg_monthly_boxes IS NULL OR h.avg_monthly_boxes = 0 THEN NULL
              ELSE round((tm.boxes::numeric / h.avg_monthly_boxes), 2) END,
         'tn'::text
  FROM this_month tm
  LEFT JOIN customers c ON c.cod_cliente::text = tm.cod_cliente
  LEFT JOIN historical h ON h.cod_cliente = tm.cod_cliente
  ORDER BY tm.boxes DESC;
$function$;

-- --- 3.4 get_procesar_pedidos_recent(integer) ----------------------
CREATE OR REPLACE FUNCTION public.get_procesar_pedidos_recent(p_limit integer DEFAULT 20)
 RETURNS TABLE(ran_at timestamp with time zone, company text, status text, orders_count integer, pedidos_generated integer, error_message text, duration_ms integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT ran_at, company, status, orders_count, pedidos_generated, error_message, duration_ms
  FROM public.procesar_pedidos_log
  WHERE EXISTS (SELECT 1 FROM public.admins a WHERE a.auth_user_id = auth.uid())
  ORDER BY ran_at DESC
  LIMIT p_limit;
$function$;

-- --- 3.5 get_procesar_pedidos_stats(integer) -----------------------
CREATE OR REPLACE FUNCTION public.get_procesar_pedidos_stats(p_days integer DEFAULT 30)
 RETURNS TABLE(total_runs bigint, ok_runs bigint, error_runs bigint, no_orders_runs bigint, total_orders_processed bigint, total_pedidos_generated bigint, success_rate numeric, last_run_at timestamp with time zone, last_run_status text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH base AS (
    SELECT * FROM public.procesar_pedidos_log
    WHERE ran_at >= now() - (p_days || ' days')::interval
      AND EXISTS (SELECT 1 FROM public.admins a WHERE a.auth_user_id = auth.uid())
  ),
  agg AS (
    SELECT COUNT(*) AS total_runs,
      COUNT(*) FILTER (WHERE status = 'ok') AS ok_runs,
      COUNT(*) FILTER (WHERE status = 'error') AS error_runs,
      COUNT(*) FILTER (WHERE status = 'no_orders') AS no_orders_runs,
      COALESCE(SUM(orders_count) FILTER (WHERE status = 'ok'), 0) AS total_orders_processed,
      COALESCE(SUM(pedidos_generated) FILTER (WHERE status = 'ok'), 0) AS total_pedidos_generated
    FROM base
  ),
  last_run AS (SELECT ran_at, status FROM base ORDER BY ran_at DESC LIMIT 1)
  SELECT a.total_runs, a.ok_runs, a.error_runs, a.no_orders_runs,
    a.total_orders_processed, a.total_pedidos_generated,
    CASE WHEN (a.ok_runs + a.error_runs) > 0
         THEN ROUND((a.ok_runs::numeric / (a.ok_runs + a.error_runs)) * 100, 1)
         ELSE 0 END,
    l.ran_at, l.status
  FROM agg a LEFT JOIN last_run l ON true;
$function$;


-- =====================================================================
-- BLOQUE 4 — DATA-02: guards de dueno-o-admin (2 funciones)
-- =====================================================================
-- ESTAS DOS NO LLEVAN GUARD DE ADMIN PURO. Las invoca un CLIENTE
-- mayorista logueado, no un admin:
--   get_my_assortment_18m       <- PaginaLK script.js:1631
--   get_customer_sales_history  <- consumida por el historial del cliente
--
-- Un guard de admin aca deja sin catalogo personalizado a los 541
-- clientes, y nada en este repo avisaria. El guard correcto es:
-- el que llama es dueno de ese cod_cliente, esta vinculado a el, o es
-- admin. Mismo criterio que get_customer_history, que ya lo hace bien.

-- --- 4.1 get_my_assortment_18m(text) -------------------------------
CREATE OR REPLACE FUNCTION public.get_my_assortment_18m(p_customer text)
 RETURNS TABLE(product_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select distinct oi.product_id
  from public.order_items oi
  join public.orders o on o.id = oi.order_id
  join public.customers c on c.id = o.customer_id
  where c.cod_cliente = p_customer::integer
    and o.created_at >= (now() - interval '18 months')
    and (
      exists (select 1 from public.admins a where a.auth_user_id = auth.uid())
      or c.auth_user_id = auth.uid()
      or exists (select 1 from public.user_customer_links l
                 where l.customer_id = c.id and l.auth_user_id = auth.uid())
    );
$function$;

-- --- 4.2 get_customer_sales_history(text) --------------------------
CREATE OR REPLACE FUNCTION public.get_customer_sales_history(p_customer_code text)
 RETURNS TABLE(order_id bigint, created_at timestamp with time zone, status text, payment_method text, subtotal numeric, total numeric, item_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select
    o.id as order_id,
    o.created_at,
    o.status,
    o.payment_method,
    o.subtotal,
    o.total,
    (select count(*) from public.order_items oi where oi.order_id = o.id) as item_count
  from public.orders o
  join public.customers c on c.id = o.customer_id
  where c.cod_cliente = p_customer_code::integer
    and (
      exists (select 1 from public.admins a where a.auth_user_id = auth.uid())
      or c.auth_user_id = auth.uid()
      or exists (select 1 from public.user_customer_links l
                 where l.customer_id = c.id and l.auth_user_id = auth.uid())
    )
  order by o.created_at desc;
$function$;

COMMIT;


-- =====================================================================
-- VERIFICACION POST-APLICACION — correr TODO despues del COMMIT
-- =====================================================================
--
-- 1) DATA-01: ya no hay ambiguedad. Debe devolver 286, no error.
--    select count(*) from get_products_public_sorted();
--
-- 2) Tipos corregidos. subcategory debe salir como array {Beach}, NO
--    como el texto '{Beach}'. pg_typeof debe decir text[].
--    select cod, subcategory, pg_typeof(subcategory)::text
--    from get_products_public_sorted() where category='Cuadros' limit 3;
--
-- 3) Los GRANT quedaron. anon tiene que estar.
--    select pg_get_userbyid(a.grantee), a.privilege_type
--    from pg_proc p cross join lateral aclexplode(p.proacl) a
--    where p.proname='get_products_public_sorted';
--
-- 4) get_my_linked_customers ya no es ambigua.
--    select count(*) from get_my_linked_customers();
--
-- 5) DATA-04: fichaje_* intacto. Comparar contra
--    baseline/fichaje-antes.txt — debe dar 34 / 32 /
--    740ef7ae109a3df76edbd8c196810b7c
--
-- 6) NO REGRESION: verificar que un admin real sigue viendo datos en las
--    5 funciones del bloque 3. Si devuelven cero filas para un admin, el
--    guard esta mal y hay que revisar la tabla admins.
--    OJO: ejecutadas desde el MCP corren como postgres/service_role, con
--    lo cual auth.uid() es NULL y el guard da falso. Eso hace que
--    devuelvan cero filas SIEMPRE desde aca. La prueba real es desde el
--    panel admin con una sesion de admin logueada.
