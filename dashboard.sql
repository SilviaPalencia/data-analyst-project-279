-- dashboard.sql
-- Todas las consultas usadas para construir el dashboard y la presentacion
-- Proyecto: Escuela online - Analitica de marketing de extremo a extremo


-- ================================================================
-- 1. ATRIBUCION LAST PAID CLICK (paso 3)
-- Identifica el ultimo canal pagado que toco a cada visitante
-- antes de convertirse en lead
-- ================================================================

WITH last_paid_sessions AS (
    SELECT
        visitor_id,
        visit_date,
        source   AS utm_source,
        medium   AS utm_medium,
        campaign AS utm_campaign,
        ROW_NUMBER() OVER (
            PARTITION BY visitor_id
            ORDER BY visit_date DESC
        ) AS visit_rank
    FROM sessions
    WHERE medium IN ('cpc', 'cpm', 'cpa', 'youtube', 'cpp', 'tg', 'social')
)
SELECT
    lps.visitor_id,
    lps.visit_date,
    lps.utm_source,
    lps.utm_medium,
    lps.utm_campaign,
    l.lead_id,
    l.created_at,
    l.amount,
    l.closing_reason,
    l.status_id
FROM last_paid_sessions lps
LEFT JOIN leads l
    ON lps.visitor_id = l.visitor_id
WHERE lps.visit_rank = 1
ORDER BY
    l.amount DESC NULLS LAST,
    lps.visit_date ASC,
    lps.utm_source ASC,
    lps.utm_medium ASC,
    lps.utm_campaign ASC;


-- ================================================================
-- 2. AGREGADO DE GASTOS, VISITAS, LEADS E INGRESOS (paso 4)
-- Vitrina diaria por utm_source + utm_medium + utm_campaign
-- ================================================================

WITH paid_clicks AS (
    SELECT
        visitor_id,
        visit_date,
        source   AS utm_source,
        medium   AS utm_medium,
        campaign AS utm_campaign,
        ROW_NUMBER() OVER (
            PARTITION BY visitor_id
            ORDER BY visit_date DESC
        ) AS visit_rank
    FROM sessions
    WHERE medium IN ('cpc', 'cpm', 'cpa', 'youtube', 'cpp', 'tg', 'social')
),
last_paid_click AS (
    SELECT
        visitor_id,
        visit_date::date AS visit_date,
        visit_date AS visit_timestamp,
        utm_source,
        utm_medium,
        utm_campaign
    FROM paid_clicks
    WHERE visit_rank = 1
),
clicks_leads AS (
    SELECT
        lpc.visit_date,
        lpc.utm_source,
        lpc.utm_medium,
        lpc.utm_campaign,
        COUNT(DISTINCT lpc.visitor_id) AS visitors_count,
        COUNT(l.lead_id) AS leads_count,
        COUNT(*) FILTER (
            WHERE l.status_id = 142 OR l.closing_reason = 'Успешная продажа'
        ) AS purchases_count,
        SUM(l.amount) FILTER (
            WHERE l.status_id = 142 OR l.closing_reason = 'Успешная продажа'
        ) AS revenue
    FROM last_paid_click lpc
    LEFT JOIN leads l
        ON lpc.visitor_id = l.visitor_id
        AND l.created_at >= lpc.visit_timestamp
    GROUP BY lpc.visit_date, lpc.utm_source, lpc.utm_medium, lpc.utm_campaign
),
ads_spent AS (
    SELECT campaign_date, utm_source, utm_medium, utm_campaign, daily_spent FROM ya_ads
    UNION ALL
    SELECT campaign_date, utm_source, utm_medium, utm_campaign, daily_spent FROM vk_ads
),
ads_agg AS (
    SELECT
        campaign_date AS visit_date,
        utm_source,
        utm_medium,
        utm_campaign,
        SUM(daily_spent) AS total_cost
    FROM ads_spent
    GROUP BY campaign_date, utm_source, utm_medium, utm_campaign
)
SELECT
    cl.visit_date,
    cl.visitors_count,
    cl.utm_source,
    cl.utm_medium,
    cl.utm_campaign,
    aa.total_cost,
    cl.leads_count,
    cl.purchases_count,
    cl.revenue
FROM clicks_leads cl
LEFT JOIN ads_agg aa
    ON cl.visit_date = aa.visit_date
    AND cl.utm_source = aa.utm_source
    AND cl.utm_medium = aa.utm_medium
    AND cl.utm_campaign = aa.utm_campaign
ORDER BY
    cl.revenue DESC NULLS LAST,
    cl.visit_date ASC,
    cl.visitors_count DESC,
    cl.utm_source ASC,
    cl.utm_medium ASC,
    cl.utm_campaign ASC;


-- ================================================================
-- 3. METRICAS AGREGADAS POR CANAL, CON CPU/CPL/CPPU/ROI (paso 5)
-- Base de datos que alimenta las tablas dinamicas del dashboard
-- (Pivot_por_source, Pivot_detallado, Pivot_tiempo, Pivot_semana,
-- Pivot_mes). Las metricas CPU, CPL, CPPU, ROI y las conversiones
-- se calculan como campos calculados dentro de Google Sheets a
-- partir de este mismo resultado, agregando por distintas
-- combinaciones de utm_source / utm_medium / utm_campaign / fecha.
-- Ver consulta 2 de este archivo: es la fuente unica de datos
-- del dashboard completo.
-- ================================================================


-- ================================================================
-- 4. DIAS HASTA QUE SE CIERRA EL 90% DE LOS LEADS (paso 6)
-- Desde el ultimo clic pagado hasta la fecha de creacion del lead
-- Resultado obtenido: 25 dias
-- ================================================================

WITH paid_clicks AS (
    SELECT
        visitor_id,
        visit_date,
        ROW_NUMBER() OVER (
            PARTITION BY visitor_id
            ORDER BY visit_date DESC
        ) AS visit_rank
    FROM sessions
    WHERE medium IN ('cpc', 'cpm', 'cpa', 'youtube', 'cpp', 'tg', 'social')
),
last_click AS (
    SELECT visitor_id, visit_date
    FROM paid_clicks
    WHERE visit_rank = 1
),
closing_days AS (
    SELECT
        EXTRACT(DAY FROM (l.created_at - lc.visit_date)) AS days_to_close
    FROM leads l
    JOIN last_click lc ON l.visitor_id = lc.visitor_id
    WHERE l.status_id = 142 OR l.closing_reason = 'Успешная продажа'
)
SELECT
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY days_to_close) AS dias_para_cerrar_90pct
FROM closing_days
WHERE days_to_close >= 0;


-- ================================================================
-- 5. CAMPANAS VS TRAFICO ORGANICO - COMPARACION ANTES/DESPUES (paso 6)
-- Compara el promedio de visitas organicas 7 dias antes vs 7 dias
-- despues del lanzamiento de cada campana. Nota: la mayoria de las
-- campanas se lanzaron el primer dia del periodo de datos
-- disponible, por lo que solo 4 campanas tienen comparacion
-- completa (las lanzadas despues del 2023-06-01).
-- ================================================================

WITH campaign_launches AS (
    SELECT campaign_name, MIN(campaign_date) AS launch_date
    FROM (
        SELECT campaign_name, campaign_date FROM ya_ads
        UNION ALL
        SELECT campaign_name, campaign_date FROM vk_ads
    ) AS all_ads
    GROUP BY campaign_name
),
organic_daily AS (
    SELECT
        visit_date::date AS visit_date,
        COUNT(*) AS organic_visits
    FROM sessions
    WHERE medium NOT IN ('cpc', 'cpm', 'cpa', 'youtube', 'cpp', 'tg', 'social')
    GROUP BY visit_date::date
)
SELECT
    cl.campaign_name,
    cl.launch_date,
    AVG(CASE WHEN od.visit_date < cl.launch_date
             AND od.visit_date >= cl.launch_date - INTERVAL '7 days'
        THEN od.organic_visits END) AS promedio_organico_antes,
    AVG(CASE WHEN od.visit_date >= cl.launch_date
             AND od.visit_date < cl.launch_date + INTERVAL '7 days'
        THEN od.organic_visits END) AS promedio_organico_despues
FROM campaign_launches cl
LEFT JOIN organic_daily od
    ON od.visit_date BETWEEN cl.launch_date - INTERVAL '7 days'
    AND cl.launch_date + INTERVAL '7 days'
GROUP BY cl.campaign_name, cl.launch_date
ORDER BY cl.launch_date;


-- ================================================================
-- 6. CORRELACION ENTRE GASTO PUBLICITARIO DIARIO Y TRAFICO
-- ORGANICO DIARIO (paso 6)
-- Version robusta del analisis anterior, usando todo el periodo
-- disponible en vez de comparar solo alrededor del lanzamiento
-- Resultado obtenido: 0.285 (correlacion positiva debil-moderada)
-- ================================================================

WITH ads_daily AS (
    SELECT campaign_date::date AS fecha, SUM(daily_spent) AS gasto_diario
    FROM (
        SELECT campaign_date, daily_spent FROM ya_ads
        UNION ALL
        SELECT campaign_date, daily_spent FROM vk_ads
    ) AS all_ads
    GROUP BY campaign_date::date
),
organic_daily AS (
    SELECT visit_date::date AS fecha, COUNT(*) AS visitas_organicas
    FROM sessions
    WHERE medium NOT IN ('cpc', 'cpm', 'cpa', 'youtube', 'cpp', 'tg', 'social')
    GROUP BY visit_date::date
)
SELECT
    CORR(a.gasto_diario, o.visitas_organicas) AS correlacion_gasto_vs_organico
FROM ads_daily a
JOIN organic_daily o ON a.fecha = o.fecha;
