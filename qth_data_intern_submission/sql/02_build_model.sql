-- 02_build_model.sql
-- Cleans raw data, quarantines invalid rows, and builds the analytics star schema.

TRUNCATE dq.quarantined_transactions;
TRUNCATE analytics.fact_transactions CASCADE;
TRUNCATE analytics.dim_date CASCADE;
TRUNCATE analytics.dim_channel CASCADE;
TRUNCATE analytics.dim_product_category CASCADE;
TRUNCATE analytics.dim_payment_method CASCADE;
TRUNCATE analytics.dim_status CASCADE;

WITH typed AS (
    SELECT
        raw_row_id,
        NULLIF(TRIM(transaction_id), '') AS transaction_id,
        NULLIF(TRIM(order_timestamp), '') AS order_timestamp_raw,
        CASE
            WHEN LOWER(TRIM(channel)) IN ('web', 'website') THEN 'Web'
            WHEN LOWER(TRIM(channel)) IN ('mobile app', 'mobile', 'app') THEN 'Mobile App'
            WHEN LOWER(TRIM(channel)) IN ('partner marketplace', 'partner', 'marketplace') THEN 'Partner Marketplace'
            ELSE NULLIF(INITCAP(TRIM(channel)), '')
        END AS channel_clean,
        NULLIF(INITCAP(TRIM(product_category)), '') AS product_category_clean,
        CASE WHEN TRIM(quantity) ~ '^-?[0-9]+$' THEN TRIM(quantity)::INT END AS quantity_int,
        CASE WHEN TRIM(amount) ~ '^-?[0-9]+(\.[0-9]+)?$' THEN ROUND(TRIM(amount)::NUMERIC, 2) END AS amount_num,
        NULLIF(TRIM(payment_method), '') AS payment_method_clean,
        NULLIF(TRIM(customer_id), '') AS customer_id,
        LOWER(NULLIF(TRIM(status), '')) AS status_clean,
        CASE
            WHEN NULLIF(TRIM(order_timestamp), '') ~ '^(19|20)\d{2}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01]) ([01]\d|2[0-3]):[0-5]\d:[0-5]\d$'
                 THEN to_timestamp(TRIM(order_timestamp), 'YYYY-MM-DD HH24:MI:SS')::timestamp
            ELSE NULL
        END AS order_ts,
        transaction_id AS transaction_id_raw,
        order_timestamp,
        channel,
        product_category,
        quantity,
        amount,
        payment_method,
        status
    FROM raw.raw_transactions
),
dedup_exact AS (
    SELECT *
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY transaction_id_raw, order_timestamp, channel, product_category,
                             quantity, amount, payment_method, customer_id, status
                ORDER BY raw_row_id
            ) AS exact_dup_rank
        FROM typed
    ) x
    WHERE exact_dup_rank = 1
),
validated AS (
    SELECT
        *,
        CONCAT_WS('; ',
            CASE WHEN transaction_id IS NULL THEN 'missing transaction_id' END,
            CASE WHEN order_ts IS NULL THEN 'missing or malformed timestamp' END,
            CASE WHEN order_ts < TIMESTAMP '2020-01-01' OR order_ts > NOW() + INTERVAL '1 day' THEN 'timestamp outside expected range' END,
            CASE WHEN channel_clean IS NULL THEN 'missing channel' END,
            CASE WHEN product_category_clean IS NULL THEN 'missing product_category' END,
            CASE WHEN quantity_int IS NULL THEN 'quantity not numeric' END,
            CASE WHEN quantity_int <= 0 THEN 'quantity is zero or negative' END,
            CASE WHEN amount_num IS NULL THEN 'amount missing or not numeric' END,
            CASE WHEN amount_num <= 0 THEN 'amount is zero or negative' END,
            CASE WHEN payment_method_clean IS NULL THEN 'missing payment_method' END,
            CASE WHEN customer_id IS NULL THEN 'missing customer_id' END,
            CASE WHEN status_clean NOT IN ('completed', 'refunded', 'failed') THEN 'unknown status' END
        ) AS invalid_reason
    FROM dedup_exact
),
valid_records AS (
    SELECT *
    FROM validated
    WHERE invalid_reason = ''
),
transaction_dedup AS (
    SELECT *
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY transaction_id
                ORDER BY order_ts DESC, raw_row_id DESC
            ) AS transaction_rank
        FROM valid_records
    ) x
    WHERE transaction_rank = 1
),
date_span AS (
    SELECT
        MIN(order_ts::date) AS min_date,
        MAX(order_ts::date) AS max_date
    FROM transaction_dedup
)
INSERT INTO dq.quarantined_transactions (
    raw_row_id, transaction_id, order_timestamp, channel, product_category, quantity,
    amount, payment_method, customer_id, status, invalid_reason
)
SELECT
    raw_row_id, transaction_id_raw, order_timestamp, channel, product_category, quantity,
    amount, payment_method, customer_id, status, invalid_reason
FROM validated
WHERE invalid_reason <> '';

WITH date_span AS (
    SELECT
        MIN(order_ts::date) AS min_date,
        MAX(order_ts::date) AS max_date
    FROM (
        SELECT
            CASE
                WHEN NULLIF(TRIM(order_timestamp), '') ~ '^(19|20)\d{2}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01]) ([01]\d|2[0-3]):[0-5]\d:[0-5]\d$'
                     THEN to_timestamp(TRIM(order_timestamp), 'YYYY-MM-DD HH24:MI:SS')::timestamp
            END AS order_ts
        FROM raw.raw_transactions
    ) s
    WHERE order_ts >= TIMESTAMP '2020-01-01'
      AND order_ts <= NOW() + INTERVAL '1 day'
)
INSERT INTO analytics.dim_date (
    date_key, date_actual, week_start, month_start, year_num, quarter_num,
    month_num, week_num, day_of_week_num, day_name, is_weekend
)
SELECT
    TO_CHAR(d::date, 'YYYYMMDD')::INT AS date_key,
    d::date AS date_actual,
    DATE_TRUNC('week', d)::date AS week_start,
    DATE_TRUNC('month', d)::date AS month_start,
    EXTRACT(YEAR FROM d)::INT AS year_num,
    EXTRACT(QUARTER FROM d)::INT AS quarter_num,
    EXTRACT(MONTH FROM d)::INT AS month_num,
    EXTRACT(WEEK FROM d)::INT AS week_num,
    EXTRACT(ISODOW FROM d)::INT AS day_of_week_num,
    TO_CHAR(d, 'FMDay') AS day_name,
    EXTRACT(ISODOW FROM d)::INT IN (6,7) AS is_weekend
FROM date_span, GENERATE_SERIES(min_date, max_date, INTERVAL '1 day') AS d;

WITH cleaned AS (
    SELECT
        raw_row_id,
        NULLIF(TRIM(transaction_id), '') AS transaction_id,
        CASE
            WHEN LOWER(TRIM(channel)) IN ('web', 'website') THEN 'Web'
            WHEN LOWER(TRIM(channel)) IN ('mobile app', 'mobile', 'app') THEN 'Mobile App'
            WHEN LOWER(TRIM(channel)) IN ('partner marketplace', 'partner', 'marketplace') THEN 'Partner Marketplace'
            ELSE NULLIF(INITCAP(TRIM(channel)), '')
        END AS channel_clean,
        NULLIF(INITCAP(TRIM(product_category)), '') AS product_category_clean,
        NULLIF(TRIM(payment_method), '') AS payment_method_clean,
        LOWER(NULLIF(TRIM(status), '')) AS status_clean,
        NULLIF(TRIM(customer_id), '') AS customer_id,
        TRIM(quantity)::INT AS quantity_int,
        ROUND(TRIM(amount)::NUMERIC, 2) AS amount_num,
        to_timestamp(TRIM(order_timestamp), 'YYYY-MM-DD HH24:MI:SS')::timestamp AS order_ts
    FROM raw.raw_transactions
    WHERE NULLIF(TRIM(order_timestamp), '') ~ '^(19|20)\d{2}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01]) ([01]\d|2[0-3]):[0-5]\d:[0-5]\d$'
      AND TRIM(quantity) ~ '^-?[0-9]+$'
      AND TRIM(amount) ~ '^-?[0-9]+(\.[0-9]+)?$'
),
valid AS (
    SELECT *
    FROM cleaned
    WHERE transaction_id IS NOT NULL
      AND order_ts >= TIMESTAMP '2020-01-01'
      AND order_ts <= NOW() + INTERVAL '1 day'
      AND channel_clean IS NOT NULL
      AND product_category_clean IS NOT NULL
      AND payment_method_clean IS NOT NULL
      AND customer_id IS NOT NULL
      AND quantity_int > 0
      AND amount_num > 0
      AND status_clean IN ('completed', 'refunded', 'failed')
),
dedup AS (
    SELECT *
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY transaction_id
                ORDER BY order_ts DESC, raw_row_id DESC
            ) AS rn
        FROM valid
    ) x
    WHERE rn = 1
)
INSERT INTO analytics.dim_channel(channel_name)
SELECT DISTINCT channel_clean FROM dedup
ON CONFLICT DO NOTHING;

WITH cleaned AS (
    SELECT NULLIF(INITCAP(TRIM(product_category)), '') AS product_category_clean
    FROM raw.raw_transactions
    WHERE NULLIF(TRIM(product_category), '') IS NOT NULL
)
INSERT INTO analytics.dim_product_category(product_category_name)
SELECT DISTINCT product_category_clean FROM cleaned
WHERE product_category_clean IS NOT NULL
ON CONFLICT DO NOTHING;

WITH cleaned AS (
    SELECT NULLIF(TRIM(payment_method), '') AS payment_method_clean
    FROM raw.raw_transactions
)
INSERT INTO analytics.dim_payment_method(payment_method_name)
SELECT DISTINCT payment_method_clean FROM cleaned
WHERE payment_method_clean IS NOT NULL
ON CONFLICT DO NOTHING;

INSERT INTO analytics.dim_status(status_name)
VALUES ('completed'), ('refunded'), ('failed')
ON CONFLICT DO NOTHING;

WITH cleaned AS (
    SELECT
        raw_row_id,
        NULLIF(TRIM(transaction_id), '') AS transaction_id,
        CASE
            WHEN LOWER(TRIM(channel)) IN ('web', 'website') THEN 'Web'
            WHEN LOWER(TRIM(channel)) IN ('mobile app', 'mobile', 'app') THEN 'Mobile App'
            WHEN LOWER(TRIM(channel)) IN ('partner marketplace', 'partner', 'marketplace') THEN 'Partner Marketplace'
            ELSE NULLIF(INITCAP(TRIM(channel)), '')
        END AS channel_clean,
        NULLIF(INITCAP(TRIM(product_category)), '') AS product_category_clean,
        NULLIF(TRIM(payment_method), '') AS payment_method_clean,
        LOWER(NULLIF(TRIM(status), '')) AS status_clean,
        NULLIF(TRIM(customer_id), '') AS customer_id,
        TRIM(quantity)::INT AS quantity_int,
        ROUND(TRIM(amount)::NUMERIC, 2) AS amount_num,
        to_timestamp(TRIM(order_timestamp), 'YYYY-MM-DD HH24:MI:SS')::timestamp AS order_ts
    FROM raw.raw_transactions
    WHERE NULLIF(TRIM(order_timestamp), '') ~ '^(19|20)\d{2}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01]) ([01]\d|2[0-3]):[0-5]\d:[0-5]\d$'
      AND TRIM(quantity) ~ '^-?[0-9]+$'
      AND TRIM(amount) ~ '^-?[0-9]+(\.[0-9]+)?$'
),
valid AS (
    SELECT *
    FROM cleaned
    WHERE transaction_id IS NOT NULL
      AND order_ts >= TIMESTAMP '2020-01-01'
      AND order_ts <= NOW() + INTERVAL '1 day'
      AND channel_clean IS NOT NULL
      AND product_category_clean IS NOT NULL
      AND payment_method_clean IS NOT NULL
      AND customer_id IS NOT NULL
      AND quantity_int > 0
      AND amount_num > 0
      AND status_clean IN ('completed', 'refunded', 'failed')
),
dedup AS (
    SELECT *
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY transaction_id
                ORDER BY order_ts DESC, raw_row_id DESC
            ) AS rn
        FROM valid
    ) x
    WHERE rn = 1
)
INSERT INTO analytics.fact_transactions (
    transaction_id, order_timestamp, date_key, channel_key, product_category_key,
    payment_method_key, status_key, customer_id, quantity, amount, is_value_eligible
)
SELECT
    d.transaction_id,
    d.order_ts,
    TO_CHAR(d.order_ts::date, 'YYYYMMDD')::INT AS date_key,
    ch.channel_key,
    pc.product_category_key,
    pm.payment_method_key,
    st.status_key,
    d.customer_id,
    d.quantity_int,
    d.amount_num,
    d.status_clean = 'completed' AS is_value_eligible
FROM dedup d
JOIN analytics.dim_channel ch ON ch.channel_name = d.channel_clean
JOIN analytics.dim_product_category pc ON pc.product_category_name = d.product_category_clean
JOIN analytics.dim_payment_method pm ON pm.payment_method_name = d.payment_method_clean
JOIN analytics.dim_status st ON st.status_name = d.status_clean;

CREATE OR REPLACE VIEW analytics.vw_weekly_growth AS
WITH weekly AS (
    SELECT
        dd.week_start,
        COUNT(*) FILTER (WHERE ft.is_value_eligible) AS completed_transactions,
        SUM(ft.quantity) FILTER (WHERE ft.is_value_eligible) AS completed_units,
        SUM(ft.amount) FILTER (WHERE ft.is_value_eligible) AS completed_value
    FROM analytics.fact_transactions ft
    JOIN analytics.dim_date dd ON dd.date_key = ft.date_key
    GROUP BY dd.week_start
)
SELECT
    week_start,
    completed_transactions,
    completed_units,
    completed_value,
    LAG(completed_value) OVER (ORDER BY week_start) AS previous_week_value,
    ROUND(
        100.0 * (completed_value - LAG(completed_value) OVER (ORDER BY week_start))
        / NULLIF(LAG(completed_value) OVER (ORDER BY week_start), 0),
        2
    ) AS wow_value_growth_pct
FROM weekly
ORDER BY week_start;

CREATE OR REPLACE VIEW analytics.vw_channel_mix AS
SELECT
    ch.channel_name,
    COUNT(*) FILTER (WHERE ft.is_value_eligible) AS completed_transactions,
    SUM(ft.quantity) FILTER (WHERE ft.is_value_eligible) AS completed_units,
    SUM(ft.amount) FILTER (WHERE ft.is_value_eligible) AS completed_value,
    ROUND(
        100.0 * SUM(ft.amount) FILTER (WHERE ft.is_value_eligible)
        / NULLIF(SUM(SUM(ft.amount) FILTER (WHERE ft.is_value_eligible)) OVER (), 0),
        2
    ) AS value_share_pct
FROM analytics.fact_transactions ft
JOIN analytics.dim_channel ch ON ch.channel_key = ft.channel_key
GROUP BY ch.channel_name
ORDER BY completed_value DESC;

CREATE OR REPLACE VIEW analytics.vw_product_category_mix AS
SELECT
    pc.product_category_name,
    COUNT(*) FILTER (WHERE ft.is_value_eligible) AS completed_transactions,
    SUM(ft.quantity) FILTER (WHERE ft.is_value_eligible) AS completed_units,
    SUM(ft.amount) FILTER (WHERE ft.is_value_eligible) AS completed_value,
    ROUND(
        100.0 * SUM(ft.amount) FILTER (WHERE ft.is_value_eligible)
        / NULLIF(SUM(SUM(ft.amount) FILTER (WHERE ft.is_value_eligible)) OVER (), 0),
        2
    ) AS value_share_pct
FROM analytics.fact_transactions ft
JOIN analytics.dim_product_category pc ON pc.product_category_key = ft.product_category_key
GROUP BY pc.product_category_name
ORDER BY completed_value DESC;

CREATE OR REPLACE VIEW analytics.vw_executive_dashboard AS
SELECT
    COUNT(*) FILTER (WHERE is_value_eligible) AS completed_transactions,
    SUM(quantity) FILTER (WHERE is_value_eligible) AS completed_units,
    SUM(amount) FILTER (WHERE is_value_eligible) AS completed_value,
    ROUND(AVG(amount) FILTER (WHERE is_value_eligible), 2) AS avg_completed_order_value,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE NOT is_value_eligible)
        / NULLIF(COUNT(*), 0),
        2
    ) AS non_completed_transaction_rate_pct
FROM analytics.fact_transactions;
