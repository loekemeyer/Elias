-- A diferencia de PaginaLK (Loekemeyer), este sitio (Tierra Nativa SA) YA
-- guarda quién confirmó cada pedido: orders.auth_user_id se completa en
-- cada insert (ver script.js, confirmación de pedido, línea ~2723).
--
-- Además, esta app no tiene la función "vendedor pide para un cliente"
-- (no hay user_customer_links ni selector "Pedir para" en script.js) —
-- así que el único origen alternativo al cliente es un admin cargando el
-- pedido desde el panel (checkbox isAdmin en el checkout).
--
-- Correr una sola vez en el SQL editor de Supabase de este proyecto.

CREATE OR REPLACE VIEW v_orders_origen AS
SELECT
  o.id AS order_id,
  o.customer_id,
  o.created_at,
  o.auth_user_id AS placed_by_auth_user_id,
  c.auth_user_id AS customer_auth_user_id,
  CASE
    WHEN o.auth_user_id IS NULL THEN 'desconocido'
    WHEN o.auth_user_id = c.auth_user_id THEN 'cliente'
    WHEN EXISTS (
      SELECT 1 FROM admins a WHERE a.auth_user_id = o.auth_user_id
    ) THEN 'admin'
    ELSE 'otro'
  END AS origen_pedido
FROM orders o
JOIN customers c ON c.id = o.customer_id;

-- Conteo:
--
--   SELECT origen_pedido, count(*)
--   FROM v_orders_origen
--   GROUP BY origen_pedido
--   ORDER BY count(*) DESC;
