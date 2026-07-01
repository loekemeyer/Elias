-- =====================================================================
-- Fix 2: Crear tablas y RPCs faltantes para TN
-- Ejecutar en SQL Editor de Supabase (zjvpzqhbekxnwxdczpof)
-- =====================================================================

-- ==================== TABLAS ====================

-- 1. loke_products (admin.js referencia, crear vacía)
CREATE TABLE IF NOT EXISTS public.loke_products (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  cod text NOT NULL,
  description text NOT NULL,
  category text NOT NULL,
  list_price numeric NOT NULL DEFAULT 0,
  uxb integer NOT NULL DEFAULT 1,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  equiv_product_id uuid,
  images text NOT NULL DEFAULT '{}'::text
);
ALTER TABLE public.loke_products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "loke_products_read" ON public.loke_products FOR SELECT TO authenticated USING (true);

-- 2. ppp_match
CREATE TABLE IF NOT EXISTS public.ppp_match (
  web_order_id bigint NOT NULL PRIMARY KEY,
  isis_np text[] NOT NULL DEFAULT '{}'::text[],
  m3_web numeric NOT NULL,
  m3_isis numeric,
  dif_m3 numeric DEFAULT (COALESCE(m3_isis, 0::numeric) - m3_web),
  status text NOT NULL,
  codigos_faltantes text[] NOT NULL DEFAULT '{}'::text[],
  note text,
  notified_at timestamptz,
  resolved_at timestamptz,
  resolved_by text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.ppp_match ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ppp_match_admin" ON public.ppp_match FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM admins WHERE auth_user_id = auth.uid()));

-- 3. sales_excluded_items
CREATE TABLE IF NOT EXISTS public.sales_excluded_items (
  item_code text NOT NULL PRIMARY KEY,
  motivo text,
  creado timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.sales_excluded_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sales_excluded_admin" ON public.sales_excluded_items FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM admins WHERE auth_user_id = auth.uid()));

-- 4. sales_item_remap
CREATE TABLE IF NOT EXISTS public.sales_item_remap (
  from_code text NOT NULL PRIMARY KEY,
  to_code text NOT NULL,
  creado timestamptz DEFAULT now()
);
ALTER TABLE public.sales_item_remap ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sales_remap_admin" ON public.sales_item_remap FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM admins WHERE auth_user_id = auth.uid()));

-- 5. supermarket_branch_mapping
CREATE SEQUENCE IF NOT EXISTS supermarket_branch_mapping_id_seq;
CREATE TABLE IF NOT EXISTS public.supermarket_branch_mapping (
  id bigint NOT NULL DEFAULT nextval('supermarket_branch_mapping_id_seq') PRIMARY KEY,
  super_key text NOT NULL,
  super_branch_id text NOT NULL,
  super_branch_name text,
  customer_id uuid,
  cod_cliente text,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE public.supermarket_branch_mapping ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sbm_admin" ON public.supermarket_branch_mapping FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM admins WHERE auth_user_id = auth.uid()));

-- 6. procesar_pedidos_log (necesario para RPCs de procesar pedidos)
CREATE TABLE IF NOT EXISTS public.procesar_pedidos_log (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  ran_at timestamptz DEFAULT now(),
  company text,
  status text NOT NULL,
  orders_count integer DEFAULT 0,
  pedidos_generated integer DEFAULT 0,
  email_subject text,
  email_to text,
  error_message text,
  row_numbers integer[],
  duration_ms integer
);
ALTER TABLE public.procesar_pedidos_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ppl_admin" ON public.procesar_pedidos_log FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM admins WHERE auth_user_id = auth.uid()));

-- ==================== RPCs ====================

-- 1. get_all_sales_lines_admin
CREATE OR REPLACE FUNCTION public.get_all_sales_lines_admin()
RETURNS TABLE(item_code text, ym text, boxes bigint)
LANGUAGE sql SECURITY DEFINER SET search_path = 'public' STABLE
AS $$
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
$$;
GRANT EXECUTE ON FUNCTION public.get_all_sales_lines_admin() TO authenticated;

-- 2. get_all_sales_lines_admin_with_customer (simplificado para TN, sin Chef)
CREATE OR REPLACE FUNCTION public.get_all_sales_lines_admin_with_customer()
RETURNS TABLE(customer_code text, item_code text, ym text, boxes bigint)
LANGUAGE sql SECURITY DEFINER SET search_path = 'public' STABLE
AS $$
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
$$;
GRANT EXECUTE ON FUNCTION public.get_all_sales_lines_admin_with_customer() TO authenticated;

-- 3. get_customer_history (simplificado para TN, sin customer_groups)
CREATE OR REPLACE FUNCTION public.get_customer_history(p_cod_cliente text)
RETURNS TABLE(customer_code text, ym text, item_code text, description text, boxes integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public'
AS $$
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
$$;
GRANT EXECUTE ON FUNCTION public.get_customer_history(text) TO authenticated;

-- 4. get_estadistica_clientes_agg
CREATE OR REPLACE FUNCTION public.get_estadistica_clientes_agg()
RETURNS TABLE(cod_cliente text, last_purchase_date date, purchase_count integer, avg_interval_days numeric)
LANGUAGE sql SECURITY DEFINER SET search_path = 'public' STABLE
AS $$
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
$$;
GRANT EXECUTE ON FUNCTION public.get_estadistica_clientes_agg() TO authenticated;

-- 5. get_estadistica_madre_detail (simplificado para TN, sin Chef, sin detect_provincia)
CREATE OR REPLACE FUNCTION public.get_estadistica_madre_detail(p_item_code text, p_ym text)
RETURNS TABLE(cod_cliente text, business_name text, provincia text, boxes bigint, unidades bigint, avg_monthly_units numeric, ratio numeric, via text)
LANGUAGE sql SECURITY DEFINER SET search_path = 'public' STABLE
AS $$
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
$$;
GRANT EXECUTE ON FUNCTION public.get_estadistica_madre_detail(text, text) TO authenticated;

-- 6. get_procesar_pedidos_recent
CREATE OR REPLACE FUNCTION public.get_procesar_pedidos_recent(p_limit integer DEFAULT 20)
RETURNS TABLE(ran_at timestamptz, company text, status text, orders_count integer, pedidos_generated integer, error_message text, duration_ms integer)
LANGUAGE sql SECURITY DEFINER SET search_path = 'public' STABLE
AS $$
  SELECT ran_at, company, status, orders_count, pedidos_generated, error_message, duration_ms
  FROM public.procesar_pedidos_log
  ORDER BY ran_at DESC
  LIMIT p_limit;
$$;
GRANT EXECUTE ON FUNCTION public.get_procesar_pedidos_recent(integer) TO authenticated;

-- 7. get_procesar_pedidos_stats
CREATE OR REPLACE FUNCTION public.get_procesar_pedidos_stats(p_days integer DEFAULT 30)
RETURNS TABLE(total_runs bigint, ok_runs bigint, error_runs bigint, no_orders_runs bigint, total_orders_processed bigint, total_pedidos_generated bigint, success_rate numeric, last_run_at timestamptz, last_run_status text)
LANGUAGE sql SECURITY DEFINER SET search_path = 'public' STABLE
AS $$
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
$$;
GRANT EXECUTE ON FUNCTION public.get_procesar_pedidos_stats(integer) TO authenticated;

-- 8. run_ppp_cross_reference (stub — no existe en LK tampoco, crear esqueleto)
CREATE OR REPLACE FUNCTION public.run_ppp_cross_reference(p_order_id bigint)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public'
AS $$
BEGIN
  RETURN jsonb_build_object('ok', true, 'message', 'PPP cross-reference not yet configured for TN');
END;
$$;
GRANT EXECUTE ON FUNCTION public.run_ppp_cross_reference(bigint) TO authenticated;

-- ==================== GRANTS GENERALES ====================
GRANT SELECT ON public.loke_products TO authenticated;
GRANT ALL ON public.ppp_match TO authenticated;
GRANT ALL ON public.sales_excluded_items TO authenticated;
GRANT ALL ON public.sales_item_remap TO authenticated;
GRANT ALL ON public.supermarket_branch_mapping TO authenticated;
GRANT ALL ON public.procesar_pedidos_log TO authenticated;
