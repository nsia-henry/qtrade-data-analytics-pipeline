# Question 1 — Synthetic Data Generation

## Requirement

Generate an additional synthetic transaction dataset with at least 1,000,000 records using the structure of the provided `transactions.csv` dataset.

## Files

* `src/generate\_synthetic.py` — reusable Python script version.
* `notebooks/01\_generate\_synthetic\_data.ipynb` — Google Colab notebook version for running the generation online.
* `data/raw/transactions.csv` — source dataset used as the statistical seed.
* `data/generated/synthetic\_transactions\_1m.csv` — generated output. This file is intentionally not committed to GitHub because it is large and reproducible.

## Approach

For synthetic data generation, I used the original `transactions.csv` file as a statistical seed rather than duplicating source rows. The generator learns observed distributions for channel, product category, payment method, status, quantity, and amount behavior. It then generates 1M+ new records across an extended 2024–2026 period, with weighted seasonality for weekends, year-end activity, and an April campaign-like bump.



The generated data also includes representative data-quality issues found in the source file, including duplicate rows, missing timestamps, malformed timestamps, missing product categories, missing/zero/negative amounts, and missing channel values. This makes the downstream cleaning pipeline testable at scale.



The generation process is available both as a reusable Python script and as a Google Colab notebook. The 1M-row CSV is not committed to GitHub because it is large and fully reproducible.Performance Considerations

The generator is designed to work in chunks. This avoids holding unnecessary intermediate data in memory and makes the process more practical for a 1M-row output. I used Google Colab for the notebook version to avoid relying on local machine resources.

The generated 1M-row file is excluded from GitHub using `.gitignore`. Reviewers can regenerate it locally or in Colab using the notebook or script.

## How to Run in Google Colab

1. Open Google Colab.
2. Upload `notebooks/01\_generate\_synthetic\_data.ipynb`.
3. Run the notebook cells in order.
4. When prompted, upload `data/raw/transactions.csv`.
5. Run the 10,000-row smoke test first.
6. Run the full 1,000,000-row generation.
7. Use the validation cells to confirm the output structure and issue counts.

## How to Run Locally

```bash
python src/generate\_synthetic.py   --input data/raw/transactions.csv   --output data/generated/synthetic\_transactions\_1m.csv   --rows 1000000
```

## GitHub Note

Do not commit `data/generated/synthetic\_transactions\_1m.csv`. Commit the generator script and notebook instead. This keeps the repository lightweight and reproducible.

