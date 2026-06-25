# Tableau Dashboard Plan

## Intended audience

The dashboard is designed for business leaders and marketplace operations teams who need a self-service view of sales performance without asking an analyst to manually pull numbers.

## Recommended data source

For fastest setup, use:

```text
outputs/tableau_clean_transactions.csv
```

For a more realistic setup, connect Tableau directly to PostgreSQL and use:

- `analytics.fact_transactions`
- `analytics.dim_date`
- `analytics.dim_channel`
- `analytics.dim_product_category`
- `analytics.dim_status`
- `analytics.vw_weekly_growth`
- `analytics.vw_channel_mix`
- `analytics.vw_product_category_mix`

## Dashboard title

**Qtrade Marketplace Performance Dashboard**

## Filters

- Date range
- Channel
- Product category
- Status

## Top KPI cards

1. Completed transaction value
2. Completed transaction volume
3. Units sold
4. Average completed order value
5. Non-completed transaction rate

These are the five numbers I would put on an executive dashboard because they answer: how big the business is, how active it is, how much product moved, how valuable each order is, and how much operational leakage exists through failed/refunded transactions.

## Visuals

### 1. Weekly completed transaction value

- Chart type: line chart
- X-axis: week start
- Y-axis: completed transaction value
- Purpose: show whether the marketplace is growing and identify spikes/dips.

### 2. Week-over-week growth

- Chart type: bar chart
- X-axis: week start
- Y-axis: week-over-week value growth %
- Purpose: make acceleration/deceleration visible.

### 3. Channel mix

- Chart type: stacked bar or horizontal bar
- Metric: completed transaction value
- Dimension: channel
- Purpose: show which channels drive value.

### 4. Product category mix

- Chart type: horizontal bar
- Metric: completed transaction value
- Dimension: product category
- Purpose: show revenue concentration by category.

### 5. Day-of-week seasonality

- Chart type: bar chart
- Metric: completed transaction value
- Dimension: day of week
- Purpose: show which days need more operational readiness.

## Actionable insight to communicate

The week beginning 2026-04-20 is materially higher than surrounding weeks. Before leadership treats this as a sustainable growth trend, the team should check whether it came from a campaign, one-off bulk activity, or a data issue.

The business is also concentrated in Web and Electronics. This means the team should protect those segments while investigating whether Mobile App, Partner Marketplace, and non-Electronics categories can grow.
