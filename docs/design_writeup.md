# Short Design Write-Up

## Data quality at scale

In production, I would implement data-quality checks at three levels: source freshness, row-level validity, and metric-level anomaly detection.

For freshness, I would monitor whether each source file/table arrived on time, whether the row count is within an expected range, and whether the latest transaction timestamp is recent. For completeness, I would alert on missing critical fields such as transaction ID, timestamp, channel, product category, customer ID, quantity, amount, payment method, and status. For validity, I would test that amounts are positive where expected, quantities are positive integers, statuses are known, timestamps are parseable, and transaction IDs are unique after deduplication.

I would also monitor business anomalies: sudden changes in completed value, refund rate, failed rate, channel share, product mix, average order value, and day-over-day or week-over-week growth. Invalid rows would be quarantined with reasons rather than silently dropped, so operations and engineering teams can investigate source-system issues.

## Scaling and extensibility

To handle 100x more data, I would move from a full-refresh process to incremental loading. Raw data would be stored append-only, and transformations would process only new or changed records using a reliable watermark such as `loaded_at`, source file date, or transaction timestamp. The fact table would keep a stable grain of one row per transaction, while source-specific logic would live in staging tables.

For a new external data source with a different structure and schedule, I would add a source-specific raw table and staging model that maps its fields into a common canonical transaction shape. The core dimensions and fact table would remain stable. This makes the warehouse extensible without rewriting the reporting layer.

## Performance

For reporting performance, I would index the fact table on date, channel, product category, status, and customer ID. At larger scale, I would partition facts by transaction date, usually monthly or weekly depending on volume. I would also create materialized views or aggregate tables for common dashboard queries such as weekly growth, channel mix, product mix, and executive KPIs.

For Tableau, I would use extracts or pre-aggregated reporting tables where appropriate, especially for executive dashboards that do not need row-level data. I would monitor query plans and refresh times as part of ongoing performance checks.

## Automation and deployment

I would turn this into a continuously updated pipeline using an orchestrator such as Airflow, Dagster, Prefect, or a simple scheduled job for a smaller setup. The pipeline would follow these steps: ingest raw data, run schema checks, clean and validate, quarantine bad records, update dimensions and facts, refresh aggregates, and publish dashboard-ready tables.

For CI/CD, I would store SQL, Python code, and tests in GitHub. Pull requests would run unit tests, SQL linting, and data-quality tests against a small sample dataset. Deployments would be zero-downtime by building new tables or partitions first, validating them, and then swapping views or promoting the new partition once checks pass.
