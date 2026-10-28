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