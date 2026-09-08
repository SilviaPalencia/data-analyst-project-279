-- last_paid_click.sql
-- Atribución Last Paid Click: último clic pagado antes de la conversión

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
