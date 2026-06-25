# QTH Data \& Analytics Intern Take-Home

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
│       └── synthetic\_transactions\_1m.csv   # created by the generation script; not committed by default
├── docs/
│   ├── dashboard\_tableau.md
│   └── design\_writeup.md
├── outputs/
│   ├── channel\_mix.csv
│   ├── dq\_summary.csv
│   ├── product\_category\_mix.csv
│   ├── tableau\_clean\_transactions.csv
│   └── weekly\_growth.csv
├── sql/
│   ├── 01\_schema.sql
│   ├── 02\_build\_model.sql
│   └── 03\_metrics.sql
├── src/
│   ├── generate\_synthetic.py
│   └── load\_postgres.py

├── notebooks/
│   ├── 01\_generate\_synthetic\_data.ipynb
│   └── docs
├── .env.example
├── .gitignore
├── docker-compose.yml
└── requirements.txt
```

## Tools used

* PostgreSQL for storage, data modeling, cleaning, and SQL analytics
* Python for repeatable loading and synthetic data generation
* Tableau for dashboarding

## Quick start

### 1\. Clone the repo

```bash
git clone <your-repo-url>
cd qth-data-intern-submission
```

### 2\. Create a virtual environment

```bash
python -m venv .venv
# Windows
.venv\\Scripts\\activate
# macOS/Linux
source .venv/bin/activate

pip install -r requirements.txt
```

### 3\. Start PostgreSQL locally

```bash
docker compose up -d
```

This creates a local PostgreSQL database using the values in `.env.example`.

### 4\. Generate the 1M-row synthetic dataset

```bash
python src/generate\_synthetic.py \\
  --input data/raw/transactions.csv \\
  --output data/generated/synthetic\_transactions\_1m.csv \\
  --rows 1000000
```

The generated dataset is intentionally not committed because it is large. It is reproducible from the script and source data.

### 5\. Load and model the source data

\- \[Question 2 — Model \& Load](docs/README\_Q2\_model\_load.md)



```bash
cp .env.example .env
python src/load\_postgres.py --input data/raw/transactions.csv
```

To load the synthetic data instead:

```bash
python src/load\_postgres.py --input data/generated/synthetic\_transactions\_1m.csv
```

### 6\. Run the analysis queries

```bash
psql "postgresql://qth\_user:qth\_password@localhost:5432/qth\_marketplace" -f sql/03\_metrics.sql
```

The same metrics are also saved in the `outputs/` folder for quick review.

## Data model

The main fact table is `analytics.fact\_transactions`.

**Grain:** one row per cleaned transaction after validation and transaction-ID deduplication.

Dimensions:

* `analytics.dim\_date`
* `analytics.dim\_channel`
* `analytics.dim\_product\_category`
* `analytics.dim\_payment\_method`
* `analytics.dim\_status`

Invalid records are not silently lost. They are written to `dq.quarantined\_transactions` with an `invalid\_reason` field so that data issues can be reviewed.

## Statuses included in value calculations

For revenue/value metrics, I include only `completed` transactions.

I exclude:

* `failed`, because the transaction did not complete.
* `refunded`, because the value should not count as retained marketplace value.

The fact table still stores all valid statuses so the business can monitor failure and refund rates separately.

## Cleaning decisions

|Issue|Decision|
|-|-|
|Exact duplicate rows|Remove duplicate raw rows before modeling|
|Duplicate `transaction\_id`|Keep one modeled record per transaction ID, prioritizing valid records and latest timestamp|
|Inconsistent channel labels|Normalize to `Web`, `Mobile App`, and `Partner Marketplace`|
|Missing/malformed timestamp|Quarantine|
|Out-of-range future timestamp|Quarantine|
|Missing channel/product category|Quarantine|
|Null, zero, or negative amount|Quarantine|
|Non-positive quantity|Quarantine|
|Unknown status|Quarantine|

## Key source-data results

After cleaning the provided source file:

* Raw rows: **4,186**
* Exact duplicate rows: **33**
* Invalid/quarantined rows after exact deduplication: **118**
* Clean modeled transactions: **4,035**
* Completed transactions used for value metrics: **3,456**
* Completed transaction value: **$344,882.34**
* Completed units sold: **5,596**

## One business insight

The week beginning **2026-04-20** is a clear spike: completed transaction value reached **$43,933.84**, more than double the previous week and about **69.7% above the 4-week rolling average**. This looks like a campaign, promotion, bulk purchase, or data issue that leadership would want explained before treating it as normal growth.

The channel and product mix also show concentration risk:

* Web contributes about **51.99%** of completed transaction value.
* Electronics contributes about **54.09%** of completed transaction value.

In plain business terms: growth is currently strongly dependent on Web and Electronics. That is good for focus, but risky if either segment slows down.

## Tableau dashboard

Use `outputs/tableau\_clean\_transactions.csv` as a quick Tableau extract, or connect Tableau directly to PostgreSQL and use:

* `analytics.fact\_transactions`
* `analytics.dim\_date`
* `analytics.dim\_channel`
* `analytics.dim\_product\_category`
* `analytics.dim\_status`
* `analytics.vw\_executive\_dashboard`
* `analytics.vw\_weekly\_growth`
* `analytics.vw\_channel\_mix`
* `analytics.vw\_product\_category\_mix`

See `docs/dashboard\_tableau.md` for the proposed dashboard layout.

## What I would do next

1. Add automated data-quality checks using dbt tests or Great Expectations.
2. Add orchestration with GitHub Actions and a scheduler such as Airflow, Dagster, or cron.
3. Create incremental loads instead of full rebuilds.
4. Add materialized weekly/monthly reporting tables for faster Tableau dashboards.
5. Add source-system reconciliation checks for refunds and failed transactions.

