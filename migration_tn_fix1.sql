-- =====================================================================
-- Fix 1: Corregir parámetros de RPCs para que coincidan con el frontend
-- Ejecutar en SQL Editor de Supabase (zjvpzqhbekxnwxdczpof)
-- =====================================================================

-- Fix get_my_assortment_18m: frontend envía p_customer (text = cod_cliente)
drop function if exists public.get_my_assortment_18m(uuid);

create or replace function public.get_my_assortment_18m(p_customer text)
returns table(product_id uuid)
language sql
security definer
set search_path = ''
stable
as $$
  select distinct oi.product_id
  from public.order_items oi
  join public.orders o on o.id = oi.order_id
  join public.customers c on c.id = o.customer_id
  where c.cod_cliente = p_customer::integer
    and o.created_at >= (now() - interval '18 months');
$$;

grant execute on function public.get_my_assortment_18m(text) to authenticated;
grant execute on function public.get_my_assortment_18m(text) to service_role;

-- Fix get_customer_sales_history: frontend envía p_customer_code (text = cod_cliente)
drop function if exists public.get_customer_sales_history(uuid);

create or replace function public.get_customer_sales_history(p_customer_code text)
returns table(
  order_id bigint,
  created_at timestamptz,
  status text,
  payment_method text,
  subtotal numeric,
  total numeric,
  item_count bigint
)
language sql
security definer
set search_path = ''
stable
as $$
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
$$;

grant execute on function public.get_customer_sales_history(text) to authenticated;
grant execute on function public.get_customer_sales_history(text) to service_role;
