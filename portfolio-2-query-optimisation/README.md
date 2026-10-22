# Portfolio 2: Query Processing and Optimisation

## Overview

This portfolio examines how PostgreSQL processes and optimises analytical and operational queries on the **VanguardPay** database. Building on the 5-table relational schema created in Portfolio 1 (`customers`, `accounts`, `transactions`, `transaction_logs`, and `beneficiaries`), the goal is to measure baseline query performance using `EXPLAIN ANALYZE`, identify bottlenecks such as sequential table scans and expensive sorts, and apply targeted indexing and query rewrites to reduce execution cost and runtime.

The queries tested in this portfolio correspond directly to core operational requirements from the VanguardPay case study:

1. **Account Statement Generation (Key Operation 7):** Retrieving a customer's complete ledger history (`transaction_logs` joined with `transactions`) for a specific account over a date range, ordered chronologically.
2. **Account Balance Auditing (Key Operation 6):** Reconciling the stored `accounts.balance` column against the sum of historical credits and debits in `transaction_logs` across all accounts to verify ledger integrity.
3. **Suspicious Activity Detection (Key Operation 8):** Identifying accounts executing rapid, high-value transfer bursts within a short time window.

---

## Dataset Scaling (`seed_large_data.sql`)

In Portfolio 1, the database held only a handful of rows to test schema constraints. With only 3 rows in a table, the PostgreSQL query planner will always choose a **Sequential Scan (`Seq Scan`)** even if an index exists, because reading a single 8 KB disk page sequentially is cheaper than reading an index page plus a table page.

To observe realistic query planner behaviour, I ran `seed_large_data.sql` to populate the database with high-volume synthetic data using `generate_series()`:

| Table | Approximate Row Count | Purpose in Testing |
|---|---|---|
| `customers` | 500 | Realistic Nigerian customer profiles across KYC states (`verified`, `pending`, `rejected`). |
| `accounts` | 800 | Savings and current accounts (customers 1–300 hold two accounts each). |
| `transactions` | 20,000 | Mix of deposits, withdrawals, and transfers over a 240-day window, including 200 planted rapid-transfer bursts across 10 accounts. |
| `transaction_logs` | ~27,000+ | Individual debit and credit ledger entries with accurate running `balance_after` values and reversal legs. |
| `beneficiaries` | ~1,000+ | 1 to 5 saved recipients per customer. |

After bulk insertion, the script runs `ANALYZE` on all five tables so the PostgreSQL query planner has up-to-date statistics on row counts and value distributions before any `EXPLAIN ANALYZE` tests are executed.
