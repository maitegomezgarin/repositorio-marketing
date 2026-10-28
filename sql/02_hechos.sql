-- =====================================================================
-- 02_hechos.sql — Tablas de HECHOS del modelo estrella
-- =====================================================================
-- Este archivo se ejecuta después de 01_dimensiones.sql porque los hechos
-- apuntan a las dimensiones con FOREIGN KEY (REFERENCES).
--
-- Para cada tabla de hechos:
--   1. Definí el GRANO: ¿qué representa UNA fila?
--      (ej.: un producto dentro de un pedido, una sesión web, una respuesta NPS)
--   2. CREATE TABLE con:
--        - PRIMARY KEY
--        - una FOREIGN KEY por cada dimensión:  product_key INTEGER REFERENCES dim_product (product_key)
--        - las métricas (cantidades, importes, puntajes...)
--   3. INSERT INTO ... SELECT uniendo las tablas de origen (raw.) con las dimensiones
--      para obtener las claves.
--
-- Patrón para obtener la clave de una dimensión:
--
--   SELECT i.order_item_id, p.product_key, i.quantity, i.line_total
--   FROM raw.sales_order_item AS i
--   JOIN dim_product AS p ON p.product_id = i.product_id
--
-- Si una FOREIGN KEY apunta a una clave que no existe en la dimensión,
-- DuckDB rechaza la carga y run_sql.py te muestra el error.
-- =====================================================================


-- TU TURNO: creá acá las tablas de hechos.

-- ---------------------------------------------------------------------
-- Hecho ventas (cabecera): UNA FILA = UN PEDIDO
-- ---------------------------------------------------------------------
-- Fuente de: Total Ventas, Ticket Promedio y Ventas por Provincia.
-- Se guarda a nivel pedido (y no a nivel producto) para que total_amount
-- no se repita en los pedidos que tienen más de un producto.
-- Se cargan TODOS los pedidos; is_sale indica cuáles cuentan como venta
-- (status PAID o FULFILLED, según la consigna y el README).
-- store_key queda vacío (NULL) en los pedidos ONLINE, que no tienen tienda.
-- La provincia sale de la dirección de envío (en tienda, es la de la tienda).
CREATE TABLE fact_sales (
    order_id        BIGINT PRIMARY KEY,                                  -- número de pedido
    date_key        INTEGER NOT NULL REFERENCES dim_date (date_key),
    customer_key    INTEGER NOT NULL REFERENCES dim_customer (customer_key),
    channel_key     INTEGER NOT NULL REFERENCES dim_channel (channel_key),
    store_key       INTEGER REFERENCES dim_store (store_key),
    province_key    INTEGER NOT NULL REFERENCES dim_province (province_key),
    order_date      TIMESTAMP NOT NULL,
    status          VARCHAR NOT NULL,
    is_sale         BOOLEAN NOT NULL,                                    -- TRUE si PAID o FULFILLED
    subtotal        DECIMAL(12, 2) NOT NULL,
    tax_amount      DECIMAL(12, 2) NOT NULL,
    shipping_fee    DECIMAL(12, 2) NOT NULL,
    total_amount    DECIMAL(12, 2) NOT NULL
);

INSERT INTO fact_sales
SELECT
    o.order_id,
    CAST(strftime(o.order_date, '%Y%m%d') AS INTEGER) AS date_key,
    cu.customer_key,
    ch.channel_key,
    st.store_key,
    pr.province_key,
    o.order_date,
    o.status,
    o.status IN ('PAID', 'FULFILLED') AS is_sale,
    o.subtotal,
    o.tax_amount,
    o.shipping_fee,
    o.total_amount
FROM raw.sales_order AS o
JOIN raw.address          AS a  ON a.address_id   = o.shipping_address_id  -- dirección de envío
JOIN dim_province         AS pr ON pr.province_id = a.province_id
JOIN dim_customer         AS cu ON cu.customer_id = o.customer_id
JOIN dim_channel          AS ch ON ch.channel_id  = o.channel_id
LEFT JOIN dim_store       AS st ON st.store_id    = o.store_id;          -- LEFT: online no tiene tienda

-- ---------------------------------------------------------------------
-- Hecho ventas (detalle): UNA FILA = UN PRODUCTO DENTRO DE UN PEDIDO
-- ---------------------------------------------------------------------
-- Fuente de: Ranking mensual de ventas por producto (suma de line_total).
-- Repite las claves del pedido (fecha, cliente, canal, tienda, provincia)
-- para poder filtrar el ranking igual que las ventas.
-- No incluye total_amount: ese importe es del pedido y está en fact_sales.
CREATE TABLE fact_sales_item (
    order_item_id    BIGINT PRIMARY KEY,
    order_id         BIGINT NOT NULL REFERENCES fact_sales (order_id),   -- pedido al que pertenece
    date_key         INTEGER NOT NULL REFERENCES dim_date (date_key),
    customer_key     INTEGER NOT NULL REFERENCES dim_customer (customer_key),
    channel_key      INTEGER NOT NULL REFERENCES dim_channel (channel_key),
    store_key        INTEGER REFERENCES dim_store (store_key),
    province_key     INTEGER NOT NULL REFERENCES dim_province (province_key),
    product_key      INTEGER NOT NULL REFERENCES dim_product (product_key),
    status           VARCHAR NOT NULL,
    is_sale          BOOLEAN NOT NULL,                                    -- TRUE si el pedido es PAID o FULFILLED
    quantity         INTEGER NOT NULL,
    unit_price       DECIMAL(12, 2) NOT NULL,
    discount_amount  DECIMAL(12, 2) NOT NULL,
    line_total       DECIMAL(12, 2) NOT NULL                              -- quantity * unit_price - discount_amount
);

INSERT INTO fact_sales_item
SELECT
    i.order_item_id,
    i.order_id,
    s.date_key,
    s.customer_key,
    s.channel_key,
    s.store_key,
    s.province_key,
    p.product_key,
    s.status,
    s.is_sale,
    i.quantity,
    i.unit_price,
    i.discount_amount,
    i.line_total
FROM raw.sales_order_item AS i
JOIN fact_sales  AS s ON s.order_id   = i.order_id      -- toma las claves ya resueltas del pedido
JOIN dim_product AS p ON p.product_id = i.product_id;

-- ---------------------------------------------------------------------
-- Hecho sesiones web: UNA FILA = UNA VISITA A LA WEB
-- ---------------------------------------------------------------------
-- Fuente de: Usuarios Activos.
-- La consigna define Usuarios Activos como COUNT(DISTINCT customer_id),
-- o session_id si la visita es anónima. Para contarlo con un solo campo,
-- active_user_id vale 'C-<customer_id>' si hay cliente o 'S-<session_id>'
-- si es anónima: COUNT(DISTINCT active_user_id) da el KPI.
-- Las visitas anónimas usan la fila "Desconocido" (customer_key = -1).
-- Todas las sesiones son de la web, por eso el canal es siempre ONLINE.
CREATE TABLE fact_web_session (
    session_id        BIGINT PRIMARY KEY,
    date_key          INTEGER NOT NULL REFERENCES dim_date (date_key),
    customer_key      INTEGER NOT NULL REFERENCES dim_customer (customer_key),
    channel_key       INTEGER NOT NULL REFERENCES dim_channel (channel_key),
    started_at        TIMESTAMP NOT NULL,
    ended_at          TIMESTAMP,                                         -- vacío si no se registró el fin
    source            VARCHAR,                                           -- ads / direct / referral / organic
    device            VARCHAR,                                           -- mobile / desktop / tablet
    is_anonymous      BOOLEAN NOT NULL,                                  -- TRUE si no inició sesión
    active_user_id    VARCHAR NOT NULL,                                  -- para contar Usuarios Activos
    duration_seconds  INTEGER                                            -- vacío si no hay ended_at
);

INSERT INTO fact_web_session
SELECT
    w.session_id,
    CAST(strftime(w.started_at, '%Y%m%d') AS INTEGER) AS date_key,
    COALESCE(cu.customer_key, -1) AS customer_key,
    ch.channel_key,
    w.started_at,
    w.ended_at,
    w.source,
    w.device,
    w.customer_id IS NULL AS is_anonymous,
    CASE
        WHEN w.customer_id IS NOT NULL THEN 'C-' || CAST(w.customer_id AS VARCHAR)
        ELSE 'S-' || CAST(w.session_id AS VARCHAR)
    END AS active_user_id,
    CAST(epoch(w.ended_at) - epoch(w.started_at) AS INTEGER) AS duration_seconds
FROM raw.web_session AS w
LEFT JOIN dim_customer AS cu ON cu.customer_id = w.customer_id          -- LEFT: hay visitas anónimas
JOIN dim_channel       AS ch ON ch.code = 'ONLINE';                     -- todas las sesiones son web

-- ---------------------------------------------------------------------
-- Hecho NPS: UNA FILA = UNA RESPUESTA A LA ENCUESTA
-- ---------------------------------------------------------------------
-- Fuente de: NPS = (% puntajes 9-10  -  % puntajes 0-6) * 100.
-- nps_value vale +100 (promotor), 0 (pasivo) o -100 (detractor):
-- el PROMEDIO de nps_value es exactamente el NPS, con cualquier filtro.
-- La encuesta no tiene número de pedido: se relaciona por cliente y canal.
-- Las respuestas anónimas usan la fila "Desconocido" (customer_key = -1).
CREATE TABLE fact_nps (
    nps_id         BIGINT PRIMARY KEY,
    date_key       INTEGER NOT NULL REFERENCES dim_date (date_key),
    customer_key   INTEGER NOT NULL REFERENCES dim_customer (customer_key),
    channel_key    INTEGER NOT NULL REFERENCES dim_channel (channel_key),
    responded_at   TIMESTAMP NOT NULL,
    score          INTEGER NOT NULL,                                     -- 0 a 10
    nps_category   VARCHAR NOT NULL,                                     -- Promotor / Pasivo / Detractor
    nps_value      INTEGER NOT NULL,                                     -- +100 / 0 / -100
    comment        VARCHAR                                               -- vacío si no dejó comentario
);

INSERT INTO fact_nps
SELECT
    n.nps_id,
    CAST(strftime(n.responded_at, '%Y%m%d') AS INTEGER) AS date_key,
    COALESCE(cu.customer_key, -1) AS customer_key,
    ch.channel_key,
    n.responded_at,
    n.score,
    CASE
        WHEN n.score >= 9 THEN 'Promotor'
        WHEN n.score >= 7 THEN 'Pasivo'
        ELSE 'Detractor'
    END AS nps_category,
    CASE
        WHEN n.score >= 9 THEN 100
        WHEN n.score >= 7 THEN 0
        ELSE -100
    END AS nps_value,
    n.comment
FROM raw.nps_response AS n
LEFT JOIN dim_customer AS cu ON cu.customer_id = n.customer_id          -- LEFT: hay respuestas anónimas
JOIN dim_channel       AS ch ON ch.channel_id  = n.channel_id;

-- ---------------------------------------------------------------------
-- Hecho envíos: UNA FILA = UN ENVÍO POR CORREO
-- ---------------------------------------------------------------------
-- Fuente de: tiempos de entrega por provincia (meta del trimestre:
-- reducir tiempos de entrega en Mendoza).
-- Solo tienen envío los pedidos que viajan por correo (online y algunos
-- que la tienda manda a domicilio). Las claves se toman del pedido.
-- Los tiempos solo existen si el envío fue entregado (DELIVERED).
CREATE TABLE fact_shipment (
    shipment_id         BIGINT PRIMARY KEY,
    order_id            BIGINT NOT NULL REFERENCES fact_sales (order_id),
    date_key            INTEGER NOT NULL REFERENCES dim_date (date_key),   -- fecha del pedido
    customer_key        INTEGER NOT NULL REFERENCES dim_customer (customer_key),
    channel_key         INTEGER NOT NULL REFERENCES dim_channel (channel_key),
    store_key           INTEGER REFERENCES dim_store (store_key),
    province_key        INTEGER NOT NULL REFERENCES dim_province (province_key),
    carrier             VARCHAR,
    tracking_number     VARCHAR,
    status              VARCHAR NOT NULL,                                  -- READY / SHIPPED / DELIVERED / CANCELLED
    order_date          TIMESTAMP NOT NULL,
    shipped_at          TIMESTAMP,
    delivered_at        TIMESTAMP,
    days_in_transit     DECIMAL(6, 2),                                     -- despacho -> entrega
    days_to_delivery    DECIMAL(6, 2)                                      -- compra -> entrega
);

INSERT INTO fact_shipment
SELECT
    sh.shipment_id,
    sh.order_id,
    s.date_key,
    s.customer_key,
    s.channel_key,
    s.store_key,
    s.province_key,
    sh.carrier,
    sh.tracking_number,
    sh.status,
    s.order_date,
    sh.shipped_at,
    sh.delivered_at,
    ROUND((epoch(sh.delivered_at) - epoch(sh.shipped_at)) / 86400, 2) AS days_in_transit,
    ROUND((epoch(sh.delivered_at) - epoch(s.order_date))  / 86400, 2) AS days_to_delivery
FROM raw.shipment AS sh
JOIN fact_sales AS s ON s.order_id = sh.order_id;          