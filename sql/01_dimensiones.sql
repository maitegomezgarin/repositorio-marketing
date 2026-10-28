-- =====================================================================
-- 01_dimensiones.sql — Tablas de DIMENSIONES del modelo estrella
-- =====================================================================
-- Para cada dimensión:
--   1. CREATE TABLE con sus columnas, tipos y PRIMARY KEY.
--   2. INSERT INTO ... SELECT para cargarla desde las tablas de origen.
--
-- Las tablas de origen (los CSV de raw/) están en el esquema raw:
--     FROM raw.product
-- Para ver qué columnas y tipos tiene una:  DESCRIBE raw.product;
-- Para explorarlas antes de escribir nada:  python run_sql.py --explorar
-- =====================================================================


-- ---------------------------------------------------------------------
-- EJEMPLO RESUELTO: dimensión producto
-- ---------------------------------------------------------------------
-- En raw/ la categoría está en otra tabla y tiene jerarquía
-- (Bottles -> Classic / Sport). En la dimensión la "aplanamos":
-- cada producto queda en una sola fila con su categoría y su familia.
--
-- product_key es la clave SUBROGADA: un número propio del data warehouse.
-- product_id es la clave NATURAL: el ID que viene del sistema de origen.
-- Las tablas de hechos usan product_key; product_id sirve para encontrarla.

CREATE TABLE dim_product (
    product_key INTEGER PRIMARY KEY,
    product_id  INTEGER NOT NULL,
    sku         VARCHAR NOT NULL,
    name        VARCHAR NOT NULL,
    category    VARCHAR,             -- Classic / Sport
    family      VARCHAR,             -- Bottles
    list_price  DECIMAL(12, 2)
);

INSERT INTO dim_product
SELECT
    ROW_NUMBER() OVER (ORDER BY p.product_id) AS product_key,
    p.product_id,
    p.sku,
    p.name,
    c.name AS category,
    f.name AS family,
    p.list_price
FROM raw.product AS p
LEFT JOIN raw.product_category AS c ON c.category_id = p.category_id   -- categoría
LEFT JOIN raw.product_category AS f ON f.category_id = c.parent_id;    -- familia (categoría padre)


-- ---------------------------------------------------------------------
-- TU TURNO: el resto de las dimensiones
-- ---------------------------------------------------------------------
-- Pensá qué preguntas tiene que responder el dashboard (por fecha, canal,
-- provincia, producto, cliente, tienda...) y creá una dimensión para cada una.
--
-- Tips:
--   * Generar todas las fechas entre dos días:
--       SELECT CAST(range AS DATE) AS fecha
--       FROM range(DATE '2024-01-01', DATE '2025-10-01', INTERVAL 1 DAY);
--   * Partes de una fecha: year(fecha), month(fecha), monthname(fecha), dayname(fecha)
--   * Clave numérica para una fecha (ej. 20240131):
--       CAST(strftime(fecha, '%Y%m%d') AS INTEGER)
--   * Si algo puede venir vacío (ej. NPS anónimos, sin cliente), podés agregar
--     una fila "Desconocido" con clave -1 y usar COALESCE(clave, -1) en los hechos.

-- ---------------------------------------------------------------------
-- Dimensión canal: ONLINE (web) y OFFLINE (tiendas)
-- ---------------------------------------------------------------------
CREATE TABLE dim_channel (
    channel_key  INTEGER PRIMARY KEY,
    channel_id   INTEGER NOT NULL,
    code         VARCHAR NOT NULL,
    name         VARCHAR NOT NULL
);

INSERT INTO dim_channel
SELECT
    ROW_NUMBER() OVER (ORDER BY c.channel_id) AS channel_key,
    c.channel_id,
    c.code,
    c.name
FROM raw.channel AS c;

-- ---------------------------------------------------------------------
-- Dimensión provincia: Buenos Aires, Córdoba, Santa Fe y Mendoza
-- ---------------------------------------------------------------------
CREATE TABLE dim_province (
    province_key  INTEGER PRIMARY KEY,
    province_id   INTEGER NOT NULL,
    name          VARCHAR NOT NULL,
    code          VARCHAR
);

INSERT INTO dim_province
SELECT
    ROW_NUMBER() OVER (ORDER BY p.province_id) AS province_key,
    p.province_id,
    p.name,
    p.code
FROM raw.province AS p;

-- ---------------------------------------------------------------------
-- Dimensión tienda: las 4 tiendas físicas (canal OFFLINE)
-- ---------------------------------------------------------------------
-- En raw/ la tienda apunta a una dirección y la dirección a una provincia.
-- En la dimensión lo "aplanamos": cada tienda con su ciudad y su provincia.
CREATE TABLE dim_store (
    store_key      INTEGER PRIMARY KEY,
    store_id       INTEGER NOT NULL,
    name           VARCHAR NOT NULL,
    city           VARCHAR,
    province_name  VARCHAR
);

INSERT INTO dim_store
SELECT
    ROW_NUMBER() OVER (ORDER BY s.store_id) AS store_key,
    s.store_id,
    s.name,
    a.city,
    p.name AS province_name
FROM raw.store AS s
LEFT JOIN raw.address  AS a ON a.address_id  = s.address_id    -- dirección de la tienda
LEFT JOIN raw.province AS p ON p.province_id = a.province_id;  -- provincia de esa dirección

-- ---------------------------------------------------------------------
-- Dimensión cliente
-- ---------------------------------------------------------------------
-- Hay sesiones web y respuestas NPS anónimas (sin customer_id).
-- Para no perderlas, se agrega una fila "Desconocido" con clave -1
-- (tip del profesor). En los hechos se usa COALESCE(clave, -1).
CREATE TABLE dim_customer (
    customer_key  INTEGER PRIMARY KEY,
    customer_id   INTEGER,              -- NULL en la fila "Desconocido"
    first_name    VARCHAR,
    last_name     VARCHAR,
    full_name     VARCHAR,
    status        VARCHAR,              -- A = activo, I = dio de baja su cuenta
    created_at    TIMESTAMP
);

-- Fila para los anónimos
INSERT INTO dim_customer VALUES (-1, NULL, NULL, NULL, 'Desconocido', NULL, NULL);

-- Clientes reales
INSERT INTO dim_customer
SELECT
    ROW_NUMBER() OVER (ORDER BY c.customer_id) AS customer_key,
    c.customer_id,
    c.first_name,
    c.last_name,
    c.first_name || ' ' || c.last_name AS full_name,
    c.status,
    c.created_at
FROM raw.customer AS c;