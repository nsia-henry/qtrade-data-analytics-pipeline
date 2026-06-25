-- 01_schema.sql
-- PostgreSQL schema for the Qtrade analytics model.

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS analytics;
CREATE SCHEMA IF NOT EXISTS dq;

DROP TABLE IF EXISTS raw.raw_transactions CASCADE;
CREATE TABLE raw.raw_transactions (
    raw_row_id BIGSERIAL PRIMARY KEY,
    transaction_id TEXT,
    order_timestamp TEXT,
    channel TEXT,
    product_category TEXT,
    quantity TEXT,
    amount TEXT,
    payment_method TEXT,
    customer_id TEXT,
    status TEXT,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DROP TABLE IF EXISTS dq.quarantined_transactions CASCADE;
CREATE TABLE dq.quarantined_transactions (
    quarantine_id BIGSERIAL PRIMARY KEY,
    raw_row_id BIGINT,
    transaction_id TEXT,
    order_timestamp TEXT,
    channel TEXT,
    product_category TEXT,
    quantity TEXT,
    amount TEXT,
    payment_method TEXT,
    customer_id TEXT,
    status TEXT,
    invalid_reason TEXT,
    quarantined_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DROP TABLE IF EXISTS analytics.fact_transactions CASCADE;
DROP TABLE IF EXISTS analytics.dim_date CASCADE;
DROP TABLE IF EXISTS analytics.dim_channel CASCADE;
DROP TABLE IF EXISTS analytics.dim_product_category CASCADE;
DROP TABLE IF EXISTS analytics.dim_payment_method CASCADE;
DROP TABLE IF EXISTS analytics.dim_status CASCADE;

CREATE TABLE analytics.dim_date (
    date_key INT PRIMARY KEY,
    date_actual DATE NOT NULL UNIQUE,
    week_start DATE NOT NULL,
    month_start DATE NOT NULL,
    year_num INT NOT NULL,
    quarter_num INT NOT NULL,
    month_num INT NOT NULL,
    week_num INT NOT NULL,
    day_of_week_num INT NOT NULL,
    day_name TEXT NOT NULL,
    is_weekend BOOLEAN NOT NULL
);

CREATE TABLE analytics.dim_channel (
    channel_key BIGSERIAL PRIMARY KEY,
    channel_name TEXT NOT NULL UNIQUE
);

CREATE TABLE analytics.dim_product_category (
    product_category_key BIGSERIAL PRIMARY KEY,
    product_category_name TEXT NOT NULL UNIQUE
);

CREATE TABLE analytics.dim_payment_method (
    payment_method_key BIGSERIAL PRIMARY KEY,
    payment_method_name TEXT NOT NULL UNIQUE
);

CREATE TABLE analytics.dim_status (
    status_key BIGSERIAL PRIMARY KEY,
    status_name TEXT NOT NULL UNIQUE
);

CREATE TABLE analytics.fact_transactions (
    transaction_id TEXT PRIMARY KEY,
    order_timestamp TIMESTAMP NOT NULL,
    date_key INT NOT NULL REFERENCES analytics.dim_date(date_key),
    channel_key BIGINT NOT NULL REFERENCES analytics.dim_channel(channel_key),
    product_category_key BIGINT NOT NULL REFERENCES analytics.dim_product_category(product_category_key),
    payment_method_key BIGINT NOT NULL REFERENCES analytics.dim_payment_method(payment_method_key),
    status_key BIGINT NOT NULL REFERENCES analytics.dim_status(status_key),
    customer_id TEXT NOT NULL,
    quantity INT NOT NULL,
    amount NUMERIC(14,2) NOT NULL,
    is_value_eligible BOOLEAN NOT NULL,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_fact_transactions_date_key ON analytics.fact_transactions(date_key);
CREATE INDEX IF NOT EXISTS idx_fact_transactions_channel_key ON analytics.fact_transactions(channel_key);
CREATE INDEX IF NOT EXISTS idx_fact_transactions_product_category_key ON analytics.fact_transactions(product_category_key);
CREATE INDEX IF NOT EXISTS idx_fact_transactions_status_key ON analytics.fact_transactions(status_key);
CREATE INDEX IF NOT EXISTS idx_fact_transactions_customer_id ON analytics.fact_transactions(customer_id);
