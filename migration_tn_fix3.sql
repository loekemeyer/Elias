-- =====================================================================
-- Fix 3: RPCs faltantes + user_customer_links + fix admin
-- Ejecutar en SQL Editor de Supabase TN (zjvpzqhbekxnwxdczpof)
-- =====================================================================

-- ==================== TABLA: user_customer_links ====================
CREATE TABLE IF NOT EXISTS public.user_customer_links (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  auth_user_id uuid NOT NULL,
  customer_id uuid NOT NULL REFERENCES customers(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(auth_user_id, customer_id)
);
ALTER TABLE public.user_customer_links ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ucl_own" ON public.user_customer_links FOR SELECT TO authenticated
  USING (auth_user_id = auth.uid());
CREATE POLICY "ucl_admin" ON public.user_customer_links FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM admins WHERE auth_user_id = auth.uid()));
GRANT ALL ON public.user_customer_links TO authenticated;

-- ==================== RPCs ====================

-- 1. submit_order_fast
CREATE OR REPLACE FUNCTION public.submit_order_fast(
  p_auth_user_id uuid,
  p_customer_id uuid,
  p_status text,
  p_payment_method text,
  p_payment_discount numeric,
  p_web_discount numeric,
  p_subtotal numeric,
  p_total numeric,
  p_items jsonb
)
RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public'
AS $$
DECLARE
  v_order_id bigint;
BEGIN
  IF p_auth_user_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: auth_user_id mismatch';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM customers c WHERE c.id = p_customer_id AND c.auth_user_id = auth.uid()
  ) AND NOT EXISTS (
    SELECT 1 FROM user_customer_links ucl WHERE ucl.auth_user_id = auth.uid() AND ucl.customer_id = p_customer_id
  ) AND NOT EXISTS (
    SELECT 1 FROM admins a WHERE a.auth_user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Unauthorized: customer mismatch';
  END IF;

  INSERT INTO orders (auth_user_id, customer_id, status, payment_method, payment_discount, web_discount, subtotal, total)
  VALUES (p_auth_user_id, p_customer_id, p_status, p_payment_method, p_payment_discount, p_web_discount, p_subtotal, p_total)
  RETURNING id INTO v_order_id;

  INSERT INTO order_items (order_id, product_id, cajas, uxb)
  SELECT
    v_order_id,
    (item->>'product_id')::uuid,
    (item->>'cajas')::int,
    (item->>'uxb')::int
  FROM jsonb_array_elements(p_items) AS item;

  RETURN v_order_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.submit_order_fast(uuid, uuid, text, text, numeric, numeric, numeric, numeric, jsonb) TO authenticated;

-- 2. edit_order_fast
CREATE OR REPLACE FUNCTION public.edit_order_fast(
  p_order_id bigint,
  p_auth_user_id uuid,
  p_customer_id uuid,
  p_payment_method text,
  p_payment_discount numeric,
  p_web_discount numeric,
  p_subtotal numeric,
  p_total numeric,
  p_items jsonb
)
RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public'
AS $$
DECLARE
  v_owner uuid;
BEGIN
  IF p_auth_user_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: auth_user_id mismatch';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM customers c WHERE c.id = p_customer_id AND c.auth_user_id = auth.uid()
  ) AND NOT EXISTS (
    SELECT 1 FROM user_customer_links ucl WHERE ucl.auth_user_id = auth.uid() AND ucl.customer_id = p_customer_id
  ) AND NOT EXISTS (
    SELECT 1 FROM admins a WHERE a.auth_user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Unauthorized: customer mismatch';
  END IF;

  SELECT o.customer_id INTO v_owner FROM orders o WHERE o.id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pedido inexistente';
  END IF;

  IF v_owner IS DISTINCT FROM p_customer_id THEN
    RAISE EXCEPTION 'Unauthorized: order does not belong to customer';
  END IF;

  UPDATE orders
     SET payment_method   = p_payment_method,
         payment_discount = p_payment_discount,
         web_discount     = p_web_discount,
         subtotal         = p_subtotal,
         total            = p_total
   WHERE id = p_order_id;

  DELETE FROM order_items WHERE order_id = p_order_id;

  INSERT INTO order_items (order_id, product_id, cajas, uxb)
  SELECT
    p_order_id,
    (item->>'product_id')::uuid,
    (item->>'cajas')::int,
    (item->>'uxb')::int
  FROM jsonb_array_elements(p_items) AS item;

  RETURN p_order_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.edit_order_fast(bigint, uuid, uuid, text, numeric, numeric, numeric, numeric, jsonb) TO authenticated;

-- 3. get_my_linked_customers
CREATE OR REPLACE FUNCTION public.get_my_linked_customers()
RETURNS TABLE(customer_id uuid, cod_cliente bigint, business_name text)
LANGUAGE sql SECURITY DEFINER SET search_path = 'public' STABLE
AS $$
  SELECT c.id, c.cod_cliente, c.business_name
  FROM user_customer_links ucl
  JOIN customers c ON c.id = ucl.customer_id
  WHERE ucl.auth_user_id = auth.uid();
$$;
GRANT EXECUTE ON FUNCTION public.get_my_linked_customers() TO authenticated;

-- 4. has_loke_access (TN no usa Loke — siempre false)
CREATE OR REPLACE FUNCTION public.has_loke_access(p_customer_id uuid)
RETURNS boolean
LANGUAGE sql SECURITY DEFINER SET search_path = 'public' STABLE
AS $$
  SELECT false;
$$;
GRANT EXECUTE ON FUNCTION public.has_loke_access(uuid) TO authenticated;

-- 5. get_customer_geo (simplificado para TN — sin detect_provincia, CDA solo tiene slot+label)
CREATE OR REPLACE FUNCTION public.get_customer_geo(p_customer_id uuid)
RETURNS TABLE(slot smallint, label text, direccion_entrega text, zona_expreso text, nombre_expreso text, provincia text, localidad text)
LANGUAGE sql SECURITY DEFINER SET search_path = 'public' STABLE
AS $$
  SELECT
    cda.slot::smallint,
    cda.label,
    ''::text AS direccion_entrega,
    ''::text AS zona_expreso,
    ''::text AS nombre_expreso,
    coalesce(c.localidad, '')::text AS provincia,
    coalesce(c.localidad, '')::text AS localidad
  FROM customer_delivery_addresses cda
  JOIN customers c ON c.id = cda.customer_id
  WHERE cda.customer_id = p_customer_id
    AND (
      EXISTS (SELECT 1 FROM user_customer_links l WHERE l.customer_id = p_customer_id AND l.auth_user_id = auth.uid())
      OR EXISTS (SELECT 1 FROM customers cc WHERE cc.id = p_customer_id AND cc.auth_user_id = auth.uid())
      OR EXISTS (SELECT 1 FROM admins a WHERE a.auth_user_id = auth.uid())
    )
  ORDER BY cda.slot;
$$;
GRANT EXECUTE ON FUNCTION public.get_customer_geo(uuid) TO authenticated;

-- 6. sugerencias_cliente (stub — TN no tiene datos de sugerencias aún)
CREATE OR REPLACE FUNCTION public.sugerencias_cliente(p_customer text)
RETURNS TABLE(cod text, description text, uxb integer, list_price numeric, product_id uuid, texto_clientes text)
LANGUAGE sql SECURITY DEFINER SET search_path = 'public' STABLE
AS $$
  SELECT NULL::text, NULL::text, NULL::integer, NULL::numeric, NULL::uuid, NULL::text WHERE false;
$$;
GRANT EXECUTE ON FUNCTION public.sugerencias_cliente(text) TO authenticated;

-- 7. novedades_marca (stub — TN no tiene datos de novedades aún)
CREATE OR REPLACE FUNCTION public.novedades_marca()
RETURNS TABLE(cod text, description text, uxb integer, list_price numeric, product_id uuid, mensaje text)
LANGUAGE sql SECURITY DEFINER SET search_path = 'public' STABLE
AS $$
  SELECT NULL::text, NULL::text, NULL::integer, NULL::numeric, NULL::uuid, NULL::text WHERE false;
$$;
GRANT EXECUTE ON FUNCTION public.novedades_marca() TO authenticated;

-- 8. get_products_public_sorted
CREATE OR REPLACE FUNCTION public.get_products_public_sorted(sort_mode text DEFAULT 'ranking')
RETURNS TABLE(id uuid, cod text, category text, subcategory text, ranking numeric, orden_catalogo numeric, description text, uxb integer, images text, badge_status text)
LANGUAGE sql SECURITY DEFINER SET search_path = 'public' STABLE
AS $$
  SELECT p.id, p.cod, p.category, p.subcategory,
         p.ranking::numeric, p.orden_catalogo::numeric,
         p.description, p.uxb::integer, p.images, p.badge_status
  FROM products p
  WHERE p.active = true
  ORDER BY
    CASE WHEN sort_mode = 'catalogo' THEN p.orden_catalogo ELSE p.ranking END NULLS LAST,
    p.description;
$$;
GRANT EXECUTE ON FUNCTION public.get_products_public_sorted(text) TO authenticated;

-- 9. set_my_pin
CREATE OR REPLACE FUNCTION public.set_my_pin(p_pin text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public'
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'no auth';
  END IF;
  UPDATE customers SET pin = p_pin WHERE auth_user_id = auth.uid();
END;
$$;
GRANT EXECUTE ON FUNCTION public.set_my_pin(text) TO authenticated;

-- ==================== FIX ADMIN ACCESS ====================
-- Asegurar que CUIT 30710305362 tenga acceso admin
-- Primero buscar el auth_user_id del customer con ese CUIT
DO $$
DECLARE
  v_auth_id uuid;
BEGIN
  SELECT auth_user_id INTO v_auth_id FROM customers WHERE cuit = '30710305362' LIMIT 1;
  IF v_auth_id IS NOT NULL THEN
    INSERT INTO admins (auth_user_id)
    VALUES (v_auth_id)
    ON CONFLICT DO NOTHING;
    RAISE NOTICE 'Admin added for auth_user_id: %', v_auth_id;
  ELSE
    RAISE NOTICE 'No customer found with CUIT 30710305362 or no auth_user_id assigned';
  END IF;
END;
$$;
