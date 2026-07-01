-- =====================================================================
-- Tierra Nativa SA — Migración: tablas faltantes, RPCs y RLS
-- Ejecutar en el SQL Editor de Supabase (proyecto zjvpzqhbekxnwxdczpof)
-- Fecha: 2026-07-01
-- =====================================================================

-- =====================================================================
-- 1. TABLAS FALTANTES
-- =====================================================================

-- 1a. order_tracking — estado de entrega de pedidos
create table if not exists public.order_tracking (
  id bigint generated always as identity primary key,
  np_number text not null,
  status text not null default 'recibido'
    check (status in ('recibido', 'programado', 'entregado')),
  fecha_entrega date,
  created_at timestamptz not null default now()
);

create index if not exists order_tracking_np_idx
  on public.order_tracking (np_number);

alter table public.order_tracking enable row level security;

create policy "Authenticated can read order_tracking"
  on public.order_tracking for select
  to authenticated
  using (true);

create policy "Service role full access order_tracking"
  on public.order_tracking for all
  to service_role
  using (true)
  with check (true);

-- 1b. user_customer_links — vendedores vinculados a clientes
create table if not exists public.user_customer_links (
  id bigint generated always as identity primary key,
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  cod_cliente integer,
  business_name text,
  created_at timestamptz not null default now(),
  unique(auth_user_id, customer_id)
);

create index if not exists ucl_auth_user_idx
  on public.user_customer_links (auth_user_id);

alter table public.user_customer_links enable row level security;

create policy "Users see own links"
  on public.user_customer_links for select
  to authenticated
  using (auth.uid() = auth_user_id);

create policy "Service role full access ucl"
  on public.user_customer_links for all
  to service_role
  using (true)
  with check (true);

-- 1c. saved_carts — borradores de pedido (máx 3 por cliente)
create table if not exists public.saved_carts (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id) on delete cascade,
  created_by_auth_user_id uuid references auth.users(id) on delete set null,
  name text,
  notes text,
  payment_method text,
  delivery_slot integer,
  delivery_label text,
  items jsonb not null default '[]'::jsonb,
  item_count integer generated always as (jsonb_array_length(items)) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists saved_carts_customer_idx
  on public.saved_carts (customer_id);

alter table public.saved_carts enable row level security;

create policy "Users see own drafts"
  on public.saved_carts for select
  to authenticated
  using (
    customer_id in (
      select c.id from public.customers c where c.auth_user_id = auth.uid()
      union
      select ucl.customer_id from public.user_customer_links ucl where ucl.auth_user_id = auth.uid()
    )
  );

create policy "Users insert own drafts"
  on public.saved_carts for insert
  to authenticated
  with check (created_by_auth_user_id = auth.uid());

create policy "Users update own drafts"
  on public.saved_carts for update
  to authenticated
  using (created_by_auth_user_id = auth.uid());

create policy "Users delete own drafts"
  on public.saved_carts for delete
  to authenticated
  using (created_by_auth_user_id = auth.uid());

create policy "Service role full access saved_carts"
  on public.saved_carts for all
  to service_role
  using (true)
  with check (true);

-- 1d. admin_otp_codes — 2FA para admin
create table if not exists public.admin_otp_codes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  code_hash text not null,
  expires_at timestamptz not null,
  used boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists admin_otp_codes_lookup_idx
  on public.admin_otp_codes (user_id, used, expires_at);

create index if not exists admin_otp_codes_rate_idx
  on public.admin_otp_codes (user_id, created_at desc);

alter table public.admin_otp_codes enable row level security;
-- No RLS policies for frontend — only service_role accesses this table.

-- =====================================================================
-- 2. RPCs (funciones PostgreSQL)
-- =====================================================================

-- 2a. submit_order_fast — crea orden + items en una transacción
create or replace function public.submit_order_fast(
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
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order_id bigint;
  item jsonb;
begin
  insert into public.orders (
    auth_user_id, customer_id, status,
    payment_method, payment_discount, web_discount,
    subtotal, total
  ) values (
    p_auth_user_id, p_customer_id, p_status,
    p_payment_method, p_payment_discount, p_web_discount,
    p_subtotal, p_total
  )
  returning id into v_order_id;

  for item in select * from jsonb_array_elements(p_items)
  loop
    insert into public.order_items (
      order_id, product_id, cajas, uxb,
      unit_list_price, unit_your_price, line_total
    ) values (
      v_order_id,
      (item->>'product_id')::uuid,
      (item->>'cajas')::integer,
      (item->>'uxb')::integer,
      (item->>'list_price')::numeric,
      (item->>'your_price')::numeric,
      (item->>'line_total')::numeric
    );
  end loop;

  return v_order_id;
end;
$$;

grant execute on function public.submit_order_fast(uuid, uuid, text, text, numeric, numeric, numeric, numeric, jsonb) to authenticated;
grant execute on function public.submit_order_fast(uuid, uuid, text, text, numeric, numeric, numeric, numeric, jsonb) to service_role;

-- 2b. edit_order_fast — reemplaza items de un pedido existente
create or replace function public.edit_order_fast(
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
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  item jsonb;
begin
  update public.orders set
    payment_method = p_payment_method,
    payment_discount = p_payment_discount,
    web_discount = p_web_discount,
    subtotal = p_subtotal,
    total = p_total
  where id = p_order_id
    and customer_id = p_customer_id;

  if not found then
    raise exception 'Order % not found or access denied', p_order_id;
  end if;

  delete from public.order_items where order_id = p_order_id;

  for item in select * from jsonb_array_elements(p_items)
  loop
    insert into public.order_items (
      order_id, product_id, cajas, uxb,
      unit_list_price, unit_your_price, line_total
    ) values (
      p_order_id,
      (item->>'product_id')::uuid,
      (item->>'cajas')::integer,
      (item->>'uxb')::integer,
      (item->>'list_price')::numeric,
      (item->>'your_price')::numeric,
      (item->>'line_total')::numeric
    );
  end loop;

  return p_order_id;
end;
$$;

grant execute on function public.edit_order_fast(bigint, uuid, uuid, text, numeric, numeric, numeric, numeric, jsonb) to authenticated;
grant execute on function public.edit_order_fast(bigint, uuid, uuid, text, numeric, numeric, numeric, numeric, jsonb) to service_role;

-- 2c. get_my_assortment_18m — productos comprados en últimos 18 meses
create or replace function public.get_my_assortment_18m(p_customer_id uuid)
returns table(product_id uuid)
language sql
security definer
set search_path = ''
stable
as $$
  select distinct oi.product_id
  from public.order_items oi
  join public.orders o on o.id = oi.order_id
  where o.customer_id = p_customer_id
    and o.created_at >= (now() - interval '18 months');
$$;

grant execute on function public.get_my_assortment_18m(uuid) to authenticated;
grant execute on function public.get_my_assortment_18m(uuid) to service_role;

-- 2d. get_my_linked_customers — clientes vinculados al vendedor
create or replace function public.get_my_linked_customers(p_auth_user_id uuid)
returns table(customer_id uuid, cod_cliente integer, business_name text)
language sql
security definer
set search_path = ''
stable
as $$
  select ucl.customer_id, ucl.cod_cliente, ucl.business_name
  from public.user_customer_links ucl
  where ucl.auth_user_id = p_auth_user_id
  order by ucl.business_name;
$$;

grant execute on function public.get_my_linked_customers(uuid) to authenticated;
grant execute on function public.get_my_linked_customers(uuid) to service_role;

-- 2e. get_customer_sales_history — historial de ventas de un cliente
create or replace function public.get_customer_sales_history(p_customer_id uuid)
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
  where o.customer_id = p_customer_id
  order by o.created_at desc;
$$;

grant execute on function public.get_customer_sales_history(uuid) to authenticated;
grant execute on function public.get_customer_sales_history(uuid) to service_role;

-- 2f. set_my_pin — cambiar PIN del usuario actual
create or replace function public.set_my_pin(p_new_pin text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.customers
  set pin = p_new_pin
  where auth_user_id = auth.uid();
end;
$$;

grant execute on function public.set_my_pin(text) to authenticated;

-- 2g. get_products_public_sorted — catálogo público ordenado
create or replace function public.get_products_public_sorted()
returns table(
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
language sql
security definer
set search_path = ''
stable
as $$
  select
    p.id, p.cod, p.category, p.subcategory,
    p.description, p.list_price, p.uxb, p.active,
    p.images, p.orden_catalogo, p.ranking, p.badge_status
  from public.products p
  where p.active = true
  order by p.orden_catalogo nulls last, p.cod;
$$;

grant execute on function public.get_products_public_sorted() to anon;
grant execute on function public.get_products_public_sorted() to authenticated;
grant execute on function public.get_products_public_sorted() to service_role;

-- 2h. get_admin_otp_secret — leer secrets del vault (solo service_role)
create or replace function public.get_admin_otp_secret(secret_name text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v text;
begin
  if secret_name not in ('RESEND_API_KEY', 'RESEND_FROM') then
    return null;
  end if;
  select decrypted_secret into v
  from vault.decrypted_secrets
  where name = secret_name
  limit 1;
  return v;
end;
$$;

revoke all on function public.get_admin_otp_secret(text) from public;
revoke all on function public.get_admin_otp_secret(text) from anon;
revoke all on function public.get_admin_otp_secret(text) from authenticated;
grant execute on function public.get_admin_otp_secret(text) to service_role;

-- =====================================================================
-- 3. RLS para tablas existentes (verificar que estén habilitadas)
-- =====================================================================

-- orders: autenticados leen sus propios pedidos
alter table public.orders enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies where tablename = 'orders' and policyname = 'Users see own orders'
  ) then
    execute $pol$
      create policy "Users see own orders"
        on public.orders for select
        to authenticated
        using (auth_user_id = auth.uid() or customer_id in (
          select ucl.customer_id from public.user_customer_links ucl where ucl.auth_user_id = auth.uid()
        ))
    $pol$;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies where tablename = 'orders' and policyname = 'Service role full access orders'
  ) then
    execute $pol$
      create policy "Service role full access orders"
        on public.orders for all
        to service_role
        using (true)
        with check (true)
    $pol$;
  end if;
end $$;

-- order_items: acceso vía service_role (las RPCs son security definer)
alter table public.order_items enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies where tablename = 'order_items' and policyname = 'Authenticated read order_items'
  ) then
    execute $pol$
      create policy "Authenticated read order_items"
        on public.order_items for select
        to authenticated
        using (
          order_id in (select id from public.orders where auth_user_id = auth.uid()
            or customer_id in (select ucl.customer_id from public.user_customer_links ucl where ucl.auth_user_id = auth.uid()))
        )
    $pol$;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies where tablename = 'order_items' and policyname = 'Service role full access order_items'
  ) then
    execute $pol$
      create policy "Service role full access order_items"
        on public.order_items for all
        to service_role
        using (true)
        with check (true)
    $pol$;
  end if;
end $$;

-- =====================================================================
-- 4. Vista v_customer_item_month (si está vacía, recrear)
-- =====================================================================
-- Esta vista agrega compras por cliente/producto/mes para detección de anomalías.
-- Si ya existe pero está vacía, es porque no hay datos de orders suficientes.
-- La vista se llena automáticamente cuando hay pedidos.

drop table if exists public.v_customer_item_month cascade;
create or replace view public.v_customer_item_month as
  select
    o.customer_id,
    oi.product_id,
    date_trunc('month', o.created_at) as month,
    sum(oi.cajas) as total_cajas
  from public.orders o
  join public.order_items oi on oi.order_id = o.id
  group by o.customer_id, oi.product_id, date_trunc('month', o.created_at);

grant select on public.v_customer_item_month to authenticated;
grant select on public.v_customer_item_month to service_role;

-- =====================================================================
-- FIN
-- =====================================================================
