-- =====================================================================
-- BASELINE FORENSE — estado de produccion ANTES de la Phase 3
-- Proyecto: zjvpzqhbekxnwxdczpof (Tierra Nativa)
-- Capturado: 2026-07-21 via pg_get_functiondef
--
-- ESTO ES EL ROLLBACK. Es ejecutable tal cual.
-- Si el DDL de los Planes 04 o 05 rompe algo, correr las definiciones
-- de este archivo restaura el estado previo exacto.
--
-- 14 definiciones = 12 nombres, 2 de ellos con 2 overloads.
-- =====================================================================


-- === get_all_sales_lines_admin() === security_definer=t lang=sql
-- DATA-02: SIN chequeo de admin pese al nombre. GRANT a authenticated.
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
  )
  SELECT item_code, ym, sum(boxes) AS boxes
  FROM raw
  WHERE ym IS NOT NULL
  GROUP BY item_code, ym;
$function$;


-- === get_all_sales_lines_admin_with_customer() === security_definer=t lang=sql
-- REFERENCIA — no se modifica. Este SI valida admin (linea del EXISTS).
CREATE OR REPLACE FUNCTION public.get_all_sales_lines_admin_with_customer()
 RETURNS TABLE(customer_code text, item_code text, ym text, boxes bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT
    sl.customer_code::text,
    sl.item_code::text,
    CASE
      WHEN sl.invoice_date::text ~ '^\d{4}-\d{2}-\d{2}'
        THEN substr(sl.invoice_date::text, 1, 7)
      ELSE NULL
    END AS ym,
    SUM(COALESCE(sl.boxes, 0))::bigint AS boxes
  FROM public.sales_lines sl
  WHERE sl.invoice_date IS NOT NULL
    AND sl.item_code IS NOT NULL
    AND sl.customer_code IS NOT NULL
    AND EXISTS (SELECT 1 FROM public.admins a WHERE a.auth_user_id = auth.uid())
  GROUP BY sl.customer_code, sl.item_code,
    CASE
      WHEN sl.invoice_date::text ~ '^\d{4}-\d{2}-\d{2}'
        THEN substr(sl.invoice_date::text, 1, 7)
      ELSE NULL
    END
  HAVING CASE
      WHEN sl.invoice_date::text ~ '^\d{4}-\d{2}-\d{2}'
        THEN substr(sl.invoice_date::text, 1, 7)
      ELSE NULL
    END IS NOT NULL;
$function$;


-- === get_customer_geo(uuid) === security_definer=t lang=sql
-- REFERENCIA — no se modifica. Patron dueno-o-vinculado-o-admin.
CREATE OR REPLACE FUNCTION public.get_customer_geo(p_customer_id uuid)
 RETURNS TABLE(slot smallint, label text, direccion_entrega text, zona_expreso text, nombre_expreso text, provincia text, localidad text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT cda.slot::smallint, cda.label, ''::text, ''::text, ''::text,
         coalesce(c.localidad,'')::text, coalesce(c.localidad,'')::text
  FROM customer_delivery_addresses cda JOIN customers c ON c.id = cda.customer_id
  WHERE cda.customer_id = p_customer_id
    AND (EXISTS (SELECT 1 FROM user_customer_links l WHERE l.customer_id = p_customer_id AND l.auth_user_id = auth.uid())
      OR EXISTS (SELECT 1 FROM customers cc WHERE cc.id = p_customer_id AND cc.auth_user_id = auth.uid())
      OR EXISTS (SELECT 1 FROM admins a WHERE a.auth_user_id = auth.uid()))
  ORDER BY cda.slot;
$function$;


-- === get_customer_history(text) === security_definer=t lang=plpgsql
-- REFERENCIA — no se modifica. Es el MEJOR modelo a copiar para DATA-02:
-- plpgsql, valida dueno-o-vinculado-o-admin, y ante rechazo hace RETURN vacio.
CREATE OR REPLACE FUNCTION public.get_customer_history(p_cod_cliente text)
 RETURNS TABLE(customer_code text, ym text, item_code text, description text, boxes integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_customer_id uuid;
  v_cod text;
  v_has_access boolean := false;
BEGIN
  IF p_cod_cliente IS NULL THEN RETURN; END IF;
  v_cod := btrim(p_cod_cliente);
  IF v_cod = '' THEN RETURN; END IF;

  SELECT id INTO v_customer_id FROM customers WHERE cod_cliente::text = v_cod LIMIT 1;
  IF v_customer_id IS NULL THEN RETURN; END IF;

  IF EXISTS (SELECT 1 FROM admins WHERE auth_user_id = auth.uid())
     OR EXISTS (SELECT 1 FROM customers WHERE id = v_customer_id AND auth_user_id = auth.uid())
     OR EXISTS (SELECT 1 FROM user_customer_links WHERE auth_user_id = auth.uid() AND customer_id = v_customer_id)
  THEN
    v_has_access := true;
  END IF;

  IF NOT v_has_access THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    sl.customer_code::text,
    to_char(date_trunc('month', sl.invoice_date::date::timestamptz), 'YYYY-MM'),
    sl.item_code::text,
    p.description::text,
    SUM(COALESCE(sl.boxes, 0::bigint))::integer AS boxes
  FROM sales_lines sl
  LEFT JOIN (SELECT products.cod, MIN(products.description) AS description FROM products GROUP BY products.cod) p
    ON p.cod = sl.item_code
  WHERE sl.invoice_date IS NOT NULL AND sl.customer_code::text = v_cod
  GROUP BY sl.customer_code, to_char(date_trunc('month', sl.invoice_date::date::timestamptz), 'YYYY-MM'), sl.item_code, p.description;
END;
$function$;


-- === get_customer_sales_history(text) === security_definer=t lang=sql
-- DATA-02: SIN chequeo. Enumerable (cod_cliente secuencial). Guard dueno-o-admin.
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
  order by o.created_at desc;
$function$;


-- === get_estadistica_clientes_agg() === security_definer=t lang=sql
-- DATA-02: SIN chequeo. Expone fechas y frecuencia de compra de TODOS los clientes.
CREATE OR REPLACE FUNCTION public.get_estadistica_clientes_agg()
 RETURNS TABLE(cod_cliente text, last_purchase_date date, purchase_count integer, avg_interval_days numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH all_dates AS (
    SELECT c.cod_cliente::text, o.created_at::date AS purchase_date
    FROM orders o JOIN customers c ON c.id = o.customer_id
    WHERE c.cod_cliente IS NOT NULL
    UNION
    SELECT sl.customer_code::text, to_date(substr(sl.invoice_date::text, 1, 10), 'YYYY-MM-DD')
    FROM sales_lines sl
    WHERE sl.customer_code IS NOT NULL
      AND sl.invoice_date::text ~ '^\d{4}-\d{2}-\d{2}'
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


-- === get_estadistica_madre_detail(text,text) === security_definer=t lang=sql
-- DATA-02: SIN chequeo. Expone business_name y localidad por cliente.
CREATE OR REPLACE FUNCTION public.get_estadistica_madre_detail(p_item_code text, p_ym text)
 RETURNS TABLE(cod_cliente text, business_name text, provincia text, boxes bigint, unidades bigint, avg_monthly_units numeric, ratio numeric, via text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH item_uxb AS (
    SELECT coalesce(uxb,1)::numeric AS uxb FROM products WHERE cod::text = p_item_code LIMIT 1
  ),
  this_month AS (
    SELECT sl.customer_code::text AS cod_cliente, sum(sl.boxes)::bigint AS boxes
    FROM sales_lines sl
    WHERE sl.item_code::text = p_item_code AND substr(sl.invoice_date::text,1,7) = p_ym
      AND sl.customer_code IS NOT NULL
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


-- === get_my_assortment_18m(text) === security_definer=t lang=sql
-- DATA-02: SIN chequeo. OJO: la llama un CLIENTE mayorista (script.js:1631),
-- no un admin. Guard dueno-o-admin, NUNCA admin puro.
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
    and o.created_at >= (now() - interval '18 months');
$function$;


-- === get_my_linked_customers() === security_definer=t lang=sql
-- DATA-01: ESTE SOBREVIVE. Usa auth.uid(), es el seguro.
CREATE OR REPLACE FUNCTION public.get_my_linked_customers()
 RETURNS TABLE(customer_id uuid, cod_cliente bigint, business_name text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT c.id, c.cod_cliente, c.business_name FROM user_customer_links ucl JOIN customers c ON c.id = ucl.customer_id WHERE ucl.auth_user_id = auth.uid();
$function$;


-- === get_my_linked_customers(uuid) === security_definer=t lang=sql
-- DATA-01: ESTE SE DROPEA. Recibe el uuid por parametro en vez de usar
-- auth.uid(): pasando otro uuid se ve la cartera ajena.
CREATE OR REPLACE FUNCTION public.get_my_linked_customers(p_auth_user_id uuid)
 RETURNS TABLE(customer_id uuid, cod_cliente integer, business_name text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select ucl.customer_id, ucl.cod_cliente, ucl.business_name
  from public.user_customer_links ucl
  where ucl.auth_user_id = p_auth_user_id
  order by ucl.business_name;
$function$;


-- === get_procesar_pedidos_recent(integer) === security_definer=t lang=sql
-- DATA-02: SIN chequeo. Admin puro.
CREATE OR REPLACE FUNCTION public.get_procesar_pedidos_recent(p_limit integer DEFAULT 20)
 RETURNS TABLE(ran_at timestamp with time zone, company text, status text, orders_count integer, pedidos_generated integer, error_message text, duration_ms integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT ran_at, company, status, orders_count, pedidos_generated, error_message, duration_ms
  FROM public.procesar_pedidos_log
  ORDER BY ran_at DESC
  LIMIT p_limit;
$function$;


-- === get_procesar_pedidos_stats(integer) === security_definer=t lang=sql
-- DATA-02: SIN chequeo. Admin puro.
CREATE OR REPLACE FUNCTION public.get_procesar_pedidos_stats(p_days integer DEFAULT 30)
 RETURNS TABLE(total_runs bigint, ok_runs bigint, error_runs bigint, no_orders_runs bigint, total_orders_processed bigint, total_pedidos_generated bigint, success_rate numeric, last_run_at timestamp with time zone, last_run_status text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH base AS (
    SELECT * FROM public.procesar_pedidos_log WHERE ran_at >= now() - (p_days || ' days')::interval
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


-- === get_products_public_sorted() === security_definer=t lang=sql
-- DATA-01: candidato a dropear SEGUN EL PLAN, pero OJO: es el unico de los
-- dos que devuelve los tipos que coinciden con la tabla products
-- (subcategory text[], images jsonb). Ver 03-01-SUMMARY.md, hallazgo del
-- desajuste de tipos. NO dropear sin resolver eso primero.
CREATE OR REPLACE FUNCTION public.get_products_public_sorted()
 RETURNS TABLE(id uuid, cod text, category text, subcategory text[], description text, list_price numeric, uxb integer, active boolean, images jsonb, orden_catalogo integer, ranking integer, badge_status text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select
    p.id, p.cod, p.category, p.subcategory,
    p.description, p.list_price, p.uxb, p.active,
    p.images, p.orden_catalogo, p.ranking, p.badge_status
  from public.products p
  where p.active = true
  order by p.orden_catalogo nulls last, p.cod;
$function$;


-- === get_products_public_sorted(text) === security_definer=t lang=sql
-- DATA-01: el que sobrevive segun el plan (ambos frontends pasan sort_mode).
-- PERO declara subcategory text e images text, mientras la tabla los tiene
-- como text[] y jsonb. Postgres hace cast de asignacion, con lo cual
-- subcategory sale como el string literal '{Beach}' — CON LLAVES.
CREATE OR REPLACE FUNCTION public.get_products_public_sorted(sort_mode text DEFAULT 'ranking'::text)
 RETURNS TABLE(id uuid, cod text, category text, subcategory text, ranking numeric, orden_catalogo numeric, description text, uxb integer, images text, badge_status text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT p.id, p.cod, p.category, p.subcategory,
         p.ranking::numeric, p.orden_catalogo::numeric,
         p.description, p.uxb::integer, p.images, p.badge_status
  FROM products p
  WHERE p.active = true
  ORDER BY
    CASE WHEN sort_mode = 'catalogo' THEN p.orden_catalogo ELSE p.ranking END NULLS LAST,
    p.description;
$function$;
