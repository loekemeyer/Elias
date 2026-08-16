-- ============================================================================
-- MÓDULO EXPO — Tierra Nativa SA (proyecto Supabase zjvpzqhbekxnwxdczpof)
-- ----------------------------------------------------------------------------
-- Port del módulo Expo de Loekemeyer (loekemeyer/PaginaLK). Toma pedidos en una
-- exposición desde el sitio mayorista, con el operador logueado como ADMIN.
--
-- CÓMO CORRERLO: pegar TODO este archivo en el SQL editor de Supabase de Tierra
-- Nativa (rol postgres) y ejecutar. Es idempotente (create if not exists /
-- add column if not exists / create or replace). No hay MCP hacia este proyecto,
-- así que se corre a mano — es el flujo normal del repo igual.
--
-- ⚠️ TRES COSAS QUE HAY QUE AJUSTAR ANTES/DESPUÉS (marcadas con AJUSTAR):
--   1) expo_config.next_cod: sembrar con (máximo cod_cliente del ERP) + 1.
--   2) expo_dto_escala: RECALCULAR los tramos con los datos de Tierra Nativa.
--      Los que están abajo son los de Loekemeyer, sirven solo de placeholder.
--   3) customers_pin_6_digits: si ya hay PINs que no son de 6 dígitos, el
--      constraint falla. Revisar antes (ver más abajo).
--
-- Diferencias contra el SQL de LK:
--   * Sin has_loke_access / loke_access (Tierra Nativa no tiene Línea Loke).
--   * Guards ADD COLUMN IF NOT EXISTS: el esquema de customers de Tierra Nativa
--     puede no traer whatsapp / direccion_fiscal / pin. Se agregan si faltan.
--   * revoke ... from anon EXPLÍCITO en las 4 RPC (en LK el archivo solo revocaba
--     de public y quedaron ejecutables por anon — acá se corrige de entrada).
-- ============================================================================


-- ============================================================================
-- 0) Columnas que el frontend del alta escribe. Se agregan solo si faltan.
--    (No tocan las que ya existan; IF NOT EXISTS es no-op sobre las presentes.)
-- ============================================================================
alter table public.customers add column if not exists cuit             text;
alter table public.customers add column if not exists dto_vol          numeric;
alter table public.customers add column if not exists vend             text;
alter table public.customers add column if not exists mail             text;
alter table public.customers add column if not exists whatsapp         text;
alter table public.customers add column if not exists direccion_fiscal text;
alter table public.customers add column if not exists localidad        text;
alter table public.customers add column if not exists pin              text;
-- auth_user_id / cod_cliente / business_name se asumen ya existentes.

alter table public.customer_delivery_addresses add column if not exists slot              int;
alter table public.customer_delivery_addresses add column if not exists label             text;
alter table public.customer_delivery_addresses add column if not exists direccion_entrega text;
alter table public.customer_delivery_addresses add column if not exists localidad         text;
alter table public.customer_delivery_addresses add column if not exists provincia         text;
alter table public.customer_delivery_addresses add column if not exists nombre_expreso    text;


-- ============================================================================
-- 1) Constraint del PIN — 6 dígitos  [recomendado]
-- ----------------------------------------------------------------------------
-- El PIN es el password del login del cliente (usuario = CUIT, clave = PIN de 6
-- dígitos). El alta genera un PIN aleatorio de 6 dígitos.
--
-- ⚠️ AJUSTAR: si en customers ya hay PINs que NO son de 6 dígitos, este ALTER
--    falla. Chequear primero:
--       select pin from public.customers where pin !~ '^\d{6}$' and pin is not null;
--    Si devuelve filas, normalizarlas antes o dejar este bloque comentado.
-- ============================================================================
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'customers_pin_6_digits'
  ) then
    alter table public.customers
      add constraint customers_pin_6_digits check (pin ~ '^\d{6}$');
  end if;
end $$;


-- ============================================================================
-- 2) expo_config + expo_peek_cod + expo_reservar_cod — contador de código
-- ----------------------------------------------------------------------------
-- Contador singleton (id=1) que asigna el código de cliente del sistema. NO se
-- deriva del padrón parcial de la web (que es solo una porción): usar el máximo
-- del ERP + 1.
-- ============================================================================
create table if not exists public.expo_config (
  id int primary key default 1,
  next_cod bigint not null,
  constraint expo_config_singleton check (id = 1)
);

-- ⚠️ AJUSTAR: reemplazar 1000 por (máximo cod_cliente del ERP de Tierra Nativa) + 1.
insert into public.expo_config (id, next_cod)
select 1, 1000 /* <<< AJUSTAR: max cod_cliente del ERP + 1 >>> */
where not exists (select 1 from public.expo_config where id = 1);

alter table public.expo_config enable row level security;
drop policy if exists expo_config_admin on public.expo_config;
create policy expo_config_admin on public.expo_config for all
  using      (exists (select 1 from public.admins a where a.auth_user_id = auth.uid()))
  with check (exists (select 1 from public.admins a where a.auth_user_id = auth.uid()));

-- peek: leer el próximo código sin consumirlo (para mostrarlo en el modal).
create or replace function public.expo_peek_cod()
returns bigint language sql security definer set search_path = public as $$
  select next_cod from public.expo_config where id = 1;
$$;

-- reservar: consume un código (incrementa el contador) y devuelve el reservado.
create or replace function public.expo_reservar_cod()
returns bigint language plpgsql security definer set search_path = public as $$
declare v bigint;
begin
  if not exists (select 1 from admins a where a.auth_user_id = auth.uid()) then
    raise exception 'no autorizado';
  end if;
  update public.expo_config set next_cod = next_cod + 1 where id = 1
    returning next_cod - 1 into v;
  return v;
end; $$;

revoke execute on function public.expo_peek_cod()     from public;
revoke execute on function public.expo_reservar_cod() from public;
revoke execute on function public.expo_peek_cod()     from anon;   -- imprescindible
revoke execute on function public.expo_reservar_cod() from anon;   -- imprescindible
grant  execute on function public.expo_peek_cod()     to authenticated, service_role;
grant  execute on function public.expo_reservar_cod() to authenticated, service_role;


-- ============================================================================
-- 3) expo_clientes_pendientes — staging para el ERP
-- ----------------------------------------------------------------------------
-- Una fila por cliente nuevo de expo. El frontend escribe este NÚCLEO de
-- columnas. (En LK la tabla se extendió con decenas de columnas que espejan el
-- maestro de ISIS para la importación; acá no hacen falta para que ande.)
-- ============================================================================
create table if not exists public.expo_clientes_pendientes (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid references public.customers(id) on delete set null,
  cod_cliente bigint,
  business_name text,
  cuit text,
  condicion_iva text,
  direccion text,           -- calle fiscal
  numero text,
  cp text,
  localidad text,
  provincia text,
  telefono text,
  whatsapp text,
  mail text,
  vend text,
  dto_vol numeric,
  pin text,
  direcciones_entrega jsonb default '[]'::jsonb,
    -- [{titulo, direccion, localidad, provincia, expreso}]
  estado text default 'pendiente',   -- 'pendiente' | 'cargado_erp'
  creado_por uuid default auth.uid(),
  creado_at timestamptz default now(),
  actualizado_at timestamptz default now()
);

alter table public.expo_clientes_pendientes enable row level security;
drop policy if exists expo_pend_admin_all on public.expo_clientes_pendientes;
create policy expo_pend_admin_all on public.expo_clientes_pendientes
  for all
  using      (exists (select 1 from public.admins a where a.auth_user_id = auth.uid()))
  with check (exists (select 1 from public.admins a where a.auth_user_id = auth.uid()));


-- ============================================================================
-- 4) expo_dto_escala — escala de descuento por volumen
-- ----------------------------------------------------------------------------
-- Filas (desde, dto 0..1). El dto se elige por el SUBTOTAL DE LISTA del carrito
-- (antes de descuento), en vivo. Editable desde el panel admin.
-- RLS: lectura abierta (la lee el catálogo del cliente), escritura admin.
-- ============================================================================
create table if not exists public.expo_dto_escala (
  id uuid primary key default gen_random_uuid(),
  desde numeric not null,      -- subtotal de lista desde el cual aplica
  dto   numeric not null,      -- fracción 0..1
  creado_at timestamptz default now()
);

alter table public.expo_dto_escala enable row level security;
drop policy if exists expo_escala_read on public.expo_dto_escala;
create policy expo_escala_read on public.expo_dto_escala for select using (true);
drop policy if exists expo_escala_admin on public.expo_dto_escala;
create policy expo_escala_admin on public.expo_dto_escala
  for all
  using      (exists (select 1 from public.admins a where a.auth_user_id = auth.uid()))
  with check (exists (select 1 from public.admins a where a.auth_user_id = auth.uid()));

-- ⚠️ AJUSTAR: estos tramos son los de Loekemeyer. RECALCULAR con los precios y
--    volúmenes de Tierra Nativa antes de usar en producción. También se pueden
--    editar después desde el panel admin (ABM → Escala Expo).
insert into public.expo_dto_escala (desde, dto)
select * from (values
  (0::numeric,       0.00::numeric),
  (600000::numeric,  0.02::numeric),
  (1000000::numeric, 0.04::numeric),
  (1500000::numeric, 0.06::numeric),
  (2300000::numeric, 0.08::numeric),
  (4000000::numeric, 0.10::numeric),
  (6000000::numeric, 0.12::numeric)
) as t(desde, dto)
where not exists (select 1 from public.expo_dto_escala);


-- ============================================================================
-- 5) buscar_cliente_expo(p_q) — buscador del popup "Elegir cliente"
-- ----------------------------------------------------------------------------
-- Busca por cód / razón social / CUIT (solo dígitos, >=4) / dirección de entrega
-- o localidad (>=3). SECURITY DEFINER, gate admin adentro, solo lectura, tope 25.
-- El cast a bigint va protegido en una variable plpgsql (un v_q::bigint suelto en
-- el WHERE se const-foldea y tira 22P02 con un CUIT con guiones).
-- ============================================================================
create or replace function public.buscar_cliente_expo(p_q text)
returns table(
  id uuid, cod_cliente bigint, business_name text, cuit text,
  dto_vol numeric, vend text, direccion text, localidad text
)
language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_q      text := btrim(coalesce(p_q, ''));
  v_digits text := regexp_replace(coalesce(p_q, ''), '\D', '', 'g');
  v_isnum  boolean := btrim(coalesce(p_q, '')) ~ '^\d+$';
  v_cod    bigint := null;
begin
  if not exists (select 1 from admins a where a.auth_user_id = auth.uid()) then
    raise exception 'no autorizado';
  end if;
  if length(v_q) < 2 then return; end if;
  if v_isnum and length(v_q) <= 18 then
    begin v_cod := v_q::bigint; exception when others then v_cod := null; end;
  end if;

  return query
  select * from (
    with matches as (
      select c.id
      from customers c
      where (v_cod is not null and c.cod_cliente = v_cod)
         or c.business_name ilike '%' || v_q || '%'
         or (length(v_digits) >= 4
             and regexp_replace(coalesce(c.cuit, ''), '\D', '', 'g') like '%' || v_digits || '%')
      union
      select da.customer_id
      from customer_delivery_addresses da
      where length(v_q) >= 3
        and (da.direccion_entrega ilike '%' || v_q || '%'
             or da.localidad ilike '%' || v_q || '%')
    )
    select distinct on (c.id)
      c.id, c.cod_cliente, c.business_name, c.cuit, c.dto_vol, c.vend,
      coalesce(nullif(c.direccion_fiscal, ''), da.direccion_entrega) as direccion,
      coalesce(nullif(c.localidad, ''), da.localidad) as localidad
    from customers c
    join matches m on m.id = c.id
    left join customer_delivery_addresses da on da.customer_id = c.id
    order by c.id, da.slot nulls last
  ) s
  order by s.cod_cliente
  limit 25;
end;
$function$;

revoke execute on function public.buscar_cliente_expo(text) from public;
revoke execute on function public.buscar_cliente_expo(text) from anon;   -- imprescindible
grant  execute on function public.buscar_cliente_expo(text) to authenticated, service_role;


-- ============================================================================
-- 6) expo_dashboard() — métricas del panel "Clientes Expo pend."
-- ----------------------------------------------------------------------------
-- jsonb con totales de staging + pedidos de orders cuyo customer_id está en el
-- staging. Gate admin adentro.
-- ============================================================================
create or replace function public.expo_dashboard()
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare v jsonb;
begin
  if not exists (select 1 from admins a where a.auth_user_id = auth.uid()) then
    raise exception 'no autorizado';
  end if;
  select jsonb_build_object(
    'clientes_total',      (select count(*) from expo_clientes_pendientes),
    'clientes_pendientes', (select count(*) from expo_clientes_pendientes where estado = 'pendiente'),
    'clientes_cargados',   (select count(*) from expo_clientes_pendientes where estado = 'cargado_erp'),
    'pedidos_count',       (select count(*) from orders o
                              where o.customer_id in (select customer_id from expo_clientes_pendientes where customer_id is not null)),
    'pedidos_monto',       (select coalesce(sum(o.total),0) from orders o
                              where o.customer_id in (select customer_id from expo_clientes_pendientes where customer_id is not null))
  ) into v;
  return v;
end;
$function$;

revoke execute on function public.expo_dashboard() from public;
revoke execute on function public.expo_dashboard() from anon;   -- imprescindible
grant  execute on function public.expo_dashboard() to authenticated, service_role;

-- ============================================================================
-- FIN. Recordá: 1) sembrar expo_config.next_cod, 2) recalcular expo_dto_escala.
-- ============================================================================
