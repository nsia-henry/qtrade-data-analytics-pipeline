# \## Question 2 — Model \& Load

# 

# \### Analytics Model

# 

# The analytics model uses a simple star-schema-inspired design. The grain of the main fact table is one cleaned transaction record per row. This supports time-series reporting by transaction date and allows business users to analyze sales by channel, product category, payment method, and transaction status.

# 

# The model contains:

# 

# \- `staging.raw\_transactions`: raw ingested source data preserved for traceability.

# \- `analytics.fact\_transactions`: cleaned and validated transaction records.

# \- `analytics.dim\_date`: calendar attributes for daily, weekly, and monthly reporting.

# \- `analytics.dim\_channel`: normalized sales channels.

# \- `analytics.dim\_product`: normalized product categories.

# \- `analytics.dim\_payment\_method`: normalized payment method labels.

# \- `analytics.quarantined\_transactions`: records excluded from the clean fact table with a reason for exclusion.

# 

# \### Cleaning and Validation Decisions

# 

# The load process removes exact duplicate rows and handles duplicate transaction IDs by keeping the first valid version while quarantining later duplicates. Timestamps are parsed into PostgreSQL timestamp values; records with missing or malformed timestamps are quarantined because they cannot support time-series reporting.

# 

# Channel labels are normalized into standard values such as `Web`, `Mobile App`, `Partner`, and `Unknown`. Product categories and payment methods are also standardized. Blank product or channel values are set to `Unknown` when the rest of the transaction is valid, because these records can still contribute to overall business metrics while preserving the uncertainty.

# 

# Records with missing, zero, or negative amounts are quarantined for the main sales fact table. Records with missing or non-positive quantities are also quarantined. Transaction statuses are normalized to lowercase values: `completed`, `refunded`, and `failed`.

# 

# For transaction value metrics, only `completed` transactions are included. Refunded and failed transactions are retained in the model for operational analysis but excluded from successful sales value calculations.

# 

# \### Repeatability

# 

# The load is designed to be repeatable. The schema script recreates the required tables, the load script imports the CSV into staging, and the transformation SQL rebuilds the analytics tables from the staged raw data. This makes the pipeline easier to rerun when a new source extract arrives.

