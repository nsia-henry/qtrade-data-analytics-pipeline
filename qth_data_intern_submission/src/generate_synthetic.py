"""Generate a realistic synthetic transactions dataset.

The generator learns basic distributions from the provided source file:
- channel label variants
- product mix
- status mix
- payment method mix
- quantity mix
- amount distribution by product category
- customer ID patterns
- weekday and month seasonality

It also injects representative data-quality issues so that the downstream pipeline
is tested at scale.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd


RNG_SEED = 42


def normalize_category(value: object) -> str | None:
    if pd.isna(value) or str(value).strip() == "":
        return None
    return str(value).strip().title()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", default="data/raw/transactions.csv")
    parser.add_argument("--output", default="data/generated/synthetic_transactions_1m.csv")
    parser.add_argument("--rows", type=int, default=1_000_000)
    parser.add_argument("--start-date", default="2024-01-01")
    parser.add_argument("--end-date", default="2026-12-31")
    parser.add_argument("--chunk-size", type=int, default=250_000)
    args = parser.parse_args()

    rng = np.random.default_rng(RNG_SEED)
    source = pd.read_csv(args.input)

    n = args.rows
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    # Use source distributions directly where possible.
    channel_values = source["channel"].dropna().astype(str).values
    channel_probs = source["channel"].value_counts(normalize=True, dropna=True)
    channel_labels = channel_probs.index.astype(str).values
    channel_p = channel_probs.values

    product_probs = source["product_category"].dropna().astype(str).str.title().value_counts(normalize=True)
    product_labels = product_probs.index.values
    product_p = product_probs.values

    status_probs = source["status"].dropna().astype(str).str.lower().value_counts(normalize=True)
    status_labels = status_probs.index.values
    status_p = status_probs.values

    payment_probs = source["payment_method"].dropna().astype(str).value_counts(normalize=True)
    payment_labels = payment_probs.index.values
    payment_p = payment_probs.values

    quantity_probs = source["quantity"].dropna().astype(int).value_counts(normalize=True).sort_index()
    quantity_labels = quantity_probs.index.values
    quantity_p = quantity_probs.values

    # Amounts vary strongly by product category, so fit per-category lognormal parameters.
    src = source.copy()
    src["product_category_clean"] = src["product_category"].map(normalize_category)
    src["amount_num"] = pd.to_numeric(src["amount"], errors="coerce")
    src = src[(src["amount_num"] > 0) & src["product_category_clean"].notna()]
    amount_params: dict[str, tuple[float, float]] = {}
    for cat, group in src.groupby("product_category_clean"):
        log_amount = np.log(group["amount_num"].clip(lower=1))
        amount_params[cat] = (float(log_amount.mean()), float(log_amount.std(ddof=0) or 0.25))

    customers = source["customer_id"].dropna().astype(str).unique()
    max_customer_num = max(
        int(str(c).replace("C", "")) for c in customers if str(c).replace("C", "").isdigit()
    )
    expanded_customer_count = max(max_customer_num * 20, 50_000)

    start = pd.Timestamp(args.start_date)
    end = pd.Timestamp(args.end_date)
    days = pd.date_range(start, end, freq="D")

    # Build a seasonal daily probability distribution.
    # Weekends are slightly heavier, Nov/Dec are slightly heavier, and a promo-like April bump is included.
    weekday_weight = np.where(days.dayofweek >= 5, 1.25, 1.0)
    month_weight = np.where(days.month.isin([11, 12]), 1.25, 1.0)
    april_campaign_weight = np.where((days.month == 4) & (days.day.between(15, 25)), 1.7, 1.0)
    day_weights = weekday_weight * month_weight * april_campaign_weight
    day_p = day_weights / day_weights.sum()

    # Representative data-quality issue rates, based on the source file scale.
    issue_rates = {
        "null_timestamp": 0.0015,
        "malformed_timestamp": 0.0015,
        "null_channel": 0.0050,
        "null_product": 0.0035,
        "null_amount": 0.0100,
        "zero_amount": 0.0020,
        "negative_amount": 0.0020,
        "duplicate_rows": 0.0080,
    }

    first_chunk = True
    next_id = 1_000_000

    for offset in range(0, n, args.chunk_size):
        size = min(args.chunk_size, n - offset)

        selected_days = rng.choice(days, size=size, p=day_p)
        seconds = rng.integers(0, 24 * 60 * 60, size=size)
        timestamps = selected_days + pd.to_timedelta(seconds, unit="s")

        categories = rng.choice(product_labels, size=size, p=product_p)
        amounts = np.empty(size)

        for cat in product_labels:
            mask = categories == cat
            mu, sigma = amount_params.get(cat, (4.0, 0.5))
            amounts[mask] = rng.lognormal(mean=mu, sigma=sigma, size=int(mask.sum()))

        amounts = np.round(amounts, 2)

        records = pd.DataFrame(
            {
                "transaction_id": [f"SYN{next_id + i}" for i in range(size)],
                "order_timestamp": timestamps.strftime("%Y-%m-%d %H:%M:%S"),
                "channel": rng.choice(channel_labels, size=size, p=channel_p),
                "product_category": categories,
                "quantity": rng.choice(quantity_labels, size=size, p=quantity_p),
                "amount": amounts,
                "payment_method": rng.choice(payment_labels, size=size, p=payment_p),
                "customer_id": [f"C{x}" for x in rng.integers(1, expanded_customer_count + 1, size=size)],
                "status": rng.choice(status_labels, size=size, p=status_p),
            }
        )

        next_id += size

        # Inject data quality issues.
        for col, rate in [
            ("order_timestamp", issue_rates["null_timestamp"]),
            ("channel", issue_rates["null_channel"]),
            ("product_category", issue_rates["null_product"]),
            ("amount", issue_rates["null_amount"]),
        ]:
            mask = rng.random(size) < rate
            records.loc[mask, col] = np.nan

        malformed_mask = rng.random(size) < issue_rates["malformed_timestamp"]
        records.loc[malformed_mask, "order_timestamp"] = "2026-13-01 99:99"

        zero_mask = rng.random(size) < issue_rates["zero_amount"]
        records.loc[zero_mask, "amount"] = 0

        negative_mask = rng.random(size) < issue_rates["negative_amount"]
        records.loc[negative_mask, "amount"] = -np.abs(records.loc[negative_mask, "amount"].astype(float))

        # Add duplicate rows to the chunk.
        dup_count = int(size * issue_rates["duplicate_rows"])
        if dup_count > 0:
            dup_rows = records.sample(n=dup_count, random_state=RNG_SEED + offset)
            records = pd.concat([records, dup_rows], ignore_index=True)

        records.to_csv(output_path, mode="w" if first_chunk else "a", index=False, header=first_chunk)
        first_chunk = False

    print(f"Wrote {output_path} with at least {n:,} base records plus representative duplicate rows.")


if __name__ == "__main__":
    main()
