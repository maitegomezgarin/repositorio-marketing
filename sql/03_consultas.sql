-- =====================================================================
-- 03_consultas.sql — Consultas para revisar el modelo y calcular KPIs
-- =====================================================================
-- Cada SELECT de este archivo se muestra en la terminal al ejecutar
-- run_sql.py. Usalo para:
--   * comprobar que las tablas se cargaron bien (cantidad de filas, nulos...)
--   * escribir las consultas clave de los KPIs que pide la consigna
--     (ventas, usuarios activos, ticket promedio, NPS, ventas por provincia,
--     ranking mensual por producto) usando las tablas del modelo estrella.
-- =====================================================================


-- Ejemplo: revisar la dimensión producto
SELECT product_key, name, category, family, list_price
FROM dim_product
ORDER BY product_key;


-- TU TURNO: agregá acá tus consultas.

-- ---------------------------------------------------------------------
-- KPI 1: Total Ventas ($) — pedidos PAID o FULFILLED
-- ---------------------------------------------------------------------
SELECT
    SUM(total_amount)                  AS total_ventas,
    ROUND(SUM(total_amount) / 1e6, 1)  AS total_ventas_millones
FROM fact_sales
WHERE is_sale;

-- Ventas por mes y canal (serie temporal)
SELECT
    d.year_month,
    c.code                 AS canal,
    SUM(f.total_amount)    AS ventas
FROM fact_sales AS f
JOIN dim_date    AS d ON d.date_key    = f.date_key
JOIN dim_channel AS c ON c.channel_key = f.channel_key
WHERE f.is_sale
GROUP BY d.year_month, c.code
ORDER BY d.year_month, c.code;


-- ---------------------------------------------------------------------
-- KPI 2: Usuarios Activos — COUNT(DISTINCT customer_id), o session_id si anónimo
-- ---------------------------------------------------------------------
SELECT
    d.year_month,
    COUNT(DISTINCT w.active_user_id) AS usuarios_activos
FROM fact_web_session AS w
JOIN dim_date AS d ON d.date_key = w.date_key
GROUP BY d.year_month
ORDER BY d.year_month;


-- ---------------------------------------------------------------------
-- KPI 3: Ticket Promedio ($) — SUM(total_amount) / COUNT(*) de los pedidos vendidos
-- ---------------------------------------------------------------------
SELECT
    c.code                                         AS canal,
    COUNT(*)                                       AS pedidos,
    ROUND(SUM(f.total_amount) / COUNT(*), 2)       AS ticket_promedio
FROM fact_sales AS f
JOIN dim_channel AS c ON c.channel_key = f.channel_key
WHERE f.is_sale
GROUP BY c.code
UNION ALL
SELECT 'TOTAL', COUNT(*), ROUND(SUM(total_amount) / COUNT(*), 2)
FROM fact_sales
WHERE is_sale;


-- ---------------------------------------------------------------------
-- KPI 4: NPS — (% 9-10  -  % 0-6) * 100, igual al promedio de nps_value
-- ---------------------------------------------------------------------
SELECT
    c.code                                                         AS canal,
    COUNT(*)                                                       AS respuestas,
    ROUND(100.0 * COUNT(*) FILTER (WHERE n.score >= 9) / COUNT(*)
        - 100.0 * COUNT(*) FILTER (WHERE n.score <= 6) / COUNT(*), 2) AS nps_formula,
    ROUND(AVG(n.nps_value), 2)                                     AS nps_promedio
FROM fact_nps AS n
JOIN dim_channel AS c ON c.channel_key = n.channel_key
GROUP BY c.code
UNION ALL
SELECT 'TOTAL', COUNT(*),
    ROUND(100.0 * COUNT(*) FILTER (WHERE score >= 9) / COUNT(*)
        - 100.0 * COUNT(*) FILTER (WHERE score <= 6) / COUNT(*), 2),
    ROUND(AVG(nps_value), 2)
FROM fact_nps;


-- ---------------------------------------------------------------------
-- KPI 5: Ventas por Provincia ($ y % del total)
-- ---------------------------------------------------------------------
SELECT
    p.name                                                          AS provincia,
    SUM(f.total_amount)                                             AS ventas,
    ROUND(100.0 * SUM(f.total_amount) / SUM(SUM(f.total_amount)) OVER (), 1) AS porcentaje
FROM fact_sales AS f
JOIN dim_province AS p ON p.province_key = f.province_key
WHERE f.is_sale
GROUP BY p.name
ORDER BY ventas DESC;


-- ---------------------------------------------------------------------
-- KPI 6: Ranking mensual de ventas por producto (suma de line_total)
-- ---------------------------------------------------------------------
SELECT
    d.year_month,
    p.name                                                          AS producto,
    SUM(i.line_total)                                               AS ventas,
    SUM(i.quantity)                                                 AS unidades,
    RANK() OVER (PARTITION BY d.year_month ORDER BY SUM(i.line_total) DESC) AS ranking
FROM fact_sales_item AS i
JOIN dim_date    AS d ON d.date_key    = i.date_key
JOIN dim_product AS p ON p.product_key = i.product_key
WHERE i.is_sale
GROUP BY d.year_month, p.name
ORDER BY d.year_month, ranking;


-- ---------------------------------------------------------------------
-- Metas del trimestre
-- ---------------------------------------------------------------------
-- Meta 1: crecer 15% las ventas en Córdoba (variación contra el trimestre anterior)
SELECT
    d.year,
    d.quarter,
    SUM(f.total_amount) AS ventas_cordoba,
    ROUND(100.0 * (SUM(f.total_amount) / LAG(SUM(f.total_amount)) OVER (ORDER BY d.year, d.quarter) - 1), 1)
        AS variacion_pct
FROM fact_sales AS f
JOIN dim_date     AS d ON d.date_key     = f.date_key
JOIN dim_province AS p ON p.province_key = f.province_key
WHERE f.is_sale AND p.name = 'Córdoba'
GROUP BY d.year, d.quarter
ORDER BY d.year, d.quarter;

-- Meta 2: reducir los tiempos de entrega en Mendoza (días promedio por trimestre)
SELECT
    d.year,
    d.quarter,
    p.name                              AS provincia,
    ROUND(AVG(s.days_to_delivery), 2)   AS dias_compra_a_entrega,
    ROUND(AVG(s.days_in_transit), 2)    AS dias_en_viaje
FROM fact_shipment AS s
JOIN dim_date     AS d ON d.date_key     = s.date_key
JOIN dim_province AS p ON p.province_key = s.province_key
WHERE s.status = 'DELIVERED' AND p.name = 'Mendoza'
GROUP BY d.year, d.quarter, p.name
ORDER BY d.year, d.quarter;