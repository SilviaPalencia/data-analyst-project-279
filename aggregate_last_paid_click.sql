-- aggregate_last_paid_click.sql
-- Vitrina de gastos publicitarios, visitas, leads e ingresos
-- usando el modelo de atribucion Last Paid Click

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
    LEFT JOIN leads l ON lpc.visitor_id = l.visitor_id
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
