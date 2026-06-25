"""Load raw transactions into PostgreSQL and rebuild the analytics model."""

from __future__ import annotations

import argparse
import os
from pathlib import Path

import psycopg2
from dotenv import load_dotenv


def run_sql_file(cursor, path: Path) -> None:
    sql = path.read_text(encoding="utf-8")
    cursor.execute(sql)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", default="data/raw/transactions.csv")
    parser.add_argument("--schema-sql", default="sql/01_schema.sql")
    parser.add_argument("--build-sql", default="sql/02_build_model.sql")
    args = parser.parse_args()

    load_dotenv()

    conn = psycopg2.connect(
        host=os.getenv("POSTGRES_HOST", "localhost"),
        port=os.getenv("POSTGRES_PORT", "5432"),
        dbname=os.getenv("POSTGRES_DB", "qth_marketplace"),
        user=os.getenv("POSTGRES_USER", "qth_user"),
        password=os.getenv("POSTGRES_PASSWORD", "qth_password"),
    )
    conn.autocommit = False

    input_path = Path(args.input)
    if not input_path.exists():
        raise FileNotFoundError(f"Input file not found: {input_path}")

    try:
        with conn.cursor() as cur:
            run_sql_file(cur, Path(args.schema_sql))

            with input_path.open("r", encoding="utf-8") as f:
                cur.copy_expert(
                    """
                    COPY raw.raw_transactions (
                        transaction_id,
                        order_timestamp,
                        channel,
                        product_category,
                        quantity,
                        amount,
                        payment_method,
                        customer_id,
                        status
                    )
                    FROM STDIN
                    WITH (FORMAT CSV, HEADER TRUE)
                    """,
                    f,
                )

            run_sql_file(cur, Path(args.build_sql))

            cur.execute("SELECT COUNT(*) FROM raw.raw_transactions;")
            raw_count = cur.fetchone()[0]
            cur.execute("SELECT COUNT(*) FROM analytics.fact_transactions;")
            fact_count = cur.fetchone()[0]
            cur.execute("SELECT COUNT(*) FROM dq.quarantined_transactions;")
            quarantine_count = cur.fetchone()[0]

        conn.commit()
        print(f"Loaded {raw_count:,} raw rows.")
        print(f"Modeled {fact_count:,} clean transactions.")
        print(f"Quarantined {quarantine_count:,} invalid rows.")
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    main()
