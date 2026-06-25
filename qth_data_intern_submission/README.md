# QTH Data & Analytics Intern Take-Home

This repository contains my PostgreSQL-based solution for the Qtrade marketplace take-home challenge.

## What this project does

1. Converts the messy transaction export into a simple analytics warehouse.
2. Generates a synthetic dataset with at least 1,000,000 records using the shape and distributions of the source file.
3. Loads raw transactions into PostgreSQL.
4. Cleans, validates, deduplicates, and quarantines invalid records.
5. Builds a small star schema for time-series reporting.
6. Produces SQL metrics for total value/volume, week-over-week growth, channel mix, and product category mix.
7. Provides a Tableau-ready extract and dashboard design.

## Repository structure

```text
.
├── data/
│   ├── raw/
│   │   └── transactions.csv
│   └── generated/
│       └── synthetic_transactions_1m.csv   # created by the generation script; not committed by default
├── docs/
│   ├── dashboard_tableau.md
│   └── design_writeup.md
├── outputs/
│   ├── channel_mix.csv
│   ├── dq_summary.csv
│   ├── product_category_mix.csv
│   ├── tableau_clean_transactions.csv
│   └── weekly_growth.csv
├── sql/
│   ├── 01_schema.sql
│   ├── 02_build_model.sql
│   └── 03_metrics.sql
├── src/
│   ├── generate_synthetic.py
│   └── load_postgres.py
├── .env.example
├── .gitignore
├── docker-compose.yml
└── requirements.txt
```

## Tools used

- PostgreSQL for storage, data modeling, cleaning, and SQL analytics
- Python for repeatable loading and synthetic data generation
- Tableau for dashboarding

## Quick start

### 1. Clone the repo

```bash
git clone <your-repo-url>
cd qth-data-intern-submission
```

### 2. Create a virtual environment

```bash
python -m venv .venv
# Windows
.venv\Scripts\activate
# macOS/Linux
source .venv/bin/activate

pip install -r requirements.txt
```

### 3. Start PostgreSQL locally

```bash
docker compose up -d
```

This creates a local PostgreSQL database using the values in `.env.example`.

### 4. Generate the 1M-row synthetic dataset

```bash
python src/generate_synthetic.py \
  --input data/raw/transactions.csv \
  --output data/generated/synthetic_transactions_1m.csv \
  --rows 1000000
```

The generated dataset is intentionally not committed because it is large. It is reproducible from the script and source data.

### 5. Load and model the source data

```bash
cp .env.example .env
python src/load_postgres.py --input data/raw/transactions.csv
```

To load the synthetic data instead:

```bash
python src/load_postgres.py --input data/generated/synthetic_transactions_1m.csv
```

### 6. Run the analysis queries

```bash
psql "postgresql://qth_user:qth_password@localhost:5432/qth_marketplace" -f sql/03_metrics.sql
```

The same metrics are also saved in the `outputs/` folder for quick review.

## Data model

The main fact table is `analytics.fact_transactions`.

**Grain:** one row per cleaned transaction after validation and transaction-ID deduplication.

Dimensions:

- `analytics.dim_date`
- `analytics.dim_channel`
- `analytics.dim_product_category`
- `analytics.dim_payment_method`
- `analytics.dim_status`

Invalid records are not silently lost. They are written to `dq.quarantined_transactions` with an `invalid_reason` field so that data issues can be reviewed.

## Statuses included in value calculations

For revenue/value metrics, I include only `completed` transactions.

I exclude:

- `failed`, because the transaction did not complete.
- `refunded`, because the value should not count as retained marketplace value.

The fact table still stores all valid statuses so the business can monitor failure and refund rates separately.

## Cleaning decisions

| Issue | Decision |
|---|---|
| Exact duplicate rows | Remove duplicate raw rows before modeling |
| Duplicate `transaction_id` | Keep one modeled record per transaction ID, prioritizing valid records and latest timestamp |
| Inconsistent channel labels | Normalize to `Web`, `Mobile App`, and `Partner Marketplace` |
| Missing/malformed timestamp | Quarantine |
| Out-of-range future timestamp | Quarantine |
| Missing channel/product category | Quarantine |
| Null, zero, or negative amount | Quarantine |
| Non-positive quantity | Quarantine |
| Unknown status | Quarantine |

## Key source-data results

After cleaning the provided source file:

- Raw rows: **4,186**
- Exact duplicate rows: **33**
- Invalid/quarantined rows after exact deduplication: **118**
- Clean modeled transactions: **4,035**
- Completed transactions used for value metrics: **3,456**
- Completed transaction value: **$344,882.34**
- Completed units sold: **5,596**

## One business insight

The week beginning **2026-04-20** is a clear spike: completed transaction value reached **$43,933.84**, more than double the previous week and about **69.7% above the 4-week rolling average**. This looks like a campaign, promotion, bulk purchase, or data issue that leadership would want explained before treating it as normal growth.

The channel and product mix also show concentration risk:

- Web contributes about **51.99%** of completed transaction value.
- Electronics contributes about **54.09%** of completed transaction value.

In plain business terms: growth is currently strongly dependent on Web and Electronics. That is good for focus, but risky if either segment slows down.

## Tableau dashboard

Use `outputs/tableau_clean_transactions.csv` as a quick Tableau extract, or connect Tableau directly to PostgreSQL and use:

- `analytics.fact_transactions`
- `analytics.dim_date`
- `analytics.dim_channel`
- `analytics.dim_product_category`
- `analytics.dim_status`
- `analytics.vw_executive_dashboard`
- `analytics.vw_weekly_growth`
- `analytics.vw_channel_mix`
- `analytics.vw_product_category_mix`

See `docs/dashboard_tableau.md` for the proposed dashboard layout.

## What I would do next

1. Add automated data-quality checks using dbt tests or Great Expectations.
2. Add orchestration with GitHub Actions and a scheduler such as Airflow, Dagster, or cron.
3. Create incremental loads instead of full rebuilds.
4. Add materialized weekly/monthly reporting tables for faster Tableau dashboards.
5. Add source-system reconciliation checks for refunds and failed transactions.
