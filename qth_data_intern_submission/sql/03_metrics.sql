-- 03_metrics.sql
-- Core business metrics for the Qtrade take-home.

-- 1. Total transaction volume and value.
-- Value includes completed transactions only.
SELECT
    COUNT(*) FILTER (WHERE ft.is_value_eligible) AS completed_transaction_volume,
    SUM(ft.quantity) FILTER (WHERE ft.is_value_eligible) AS completed_units,
    SUM(ft.amount) FILTER (WHERE ft.is_value_eligible) AS completed_transaction_value,
    ROUND(AVG(ft.amount) FILTER (WHERE ft.is_value_eligible), 2) AS avg_completed_order_value
FROM analytics.fact_transactions ft;

-- 2. Status distribution.
SELECT
    st.status_name,
    COUNT(*) AS transactions,
    SUM(ft.amount) AS gross_amount_before_status_filter
FROM analytics.fact_transactions ft
JOIN analytics.dim_status st ON st.status_key = ft.status_key
GROUP BY st.status_name
ORDER BY transactions DESC;

-- 3. Week-over-week growth in completed transaction value.
SELECT *
FROM analytics.vw_weekly_growth;

-- 4. Channel mix.
SELECT *
FROM analytics.vw_channel_mix;

-- 5. Product category mix.
SELECT *
FROM analytics.vw_product_category_mix;

-- 6. Weekly anomaly check: weeks materially above/below the 4-week moving average.
WITH weekly AS (
    SELECT *
    FROM analytics.vw_weekly_growth
),
scored AS (
    SELECT
        *,
        AVG(completed_value) OVER (
            ORDER BY week_start
            ROWS BETWEEN 3 PRECEDING AND CURRENT ROW
        ) AS rolling_4wk_avg
    FROM weekly
)
SELECT
    week_start,
    completed_transactions,
    completed_value,
    ROUND(100.0 * (completed_value / NULLIF(rolling_4wk_avg, 0) - 1), 2) AS pct_vs_4wk_avg
FROM scored
WHERE rolling_4wk_avg IS NOT NULL
ORDER BY ABS(completed_value / NULLIF(rolling_4wk_avg, 0) - 1) DESC;

-- 7. Day-of-week seasonality.
SELECT
    dd.day_name,
    dd.day_of_week_num,
    COUNT(*) FILTER (WHERE ft.is_value_eligible) AS completed_transactions,
    SUM(ft.amount) FILTER (WHERE ft.is_value_eligible) AS completed_value
FROM analytics.fact_transactions ft
JOIN analytics.dim_date dd ON dd.date_key = ft.date_key
GROUP BY dd.day_name, dd.day_of_week_num
ORDER BY dd.day_of_week_num;
