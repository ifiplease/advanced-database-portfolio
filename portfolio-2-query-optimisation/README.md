# Portfolio 2: Query Processing and Optimisation

**Case study:** VanguardPay (simulated Nigerian fintech)  
**Database system:** PostgreSQL, managed with pgAdmin 4

## Goal

The goal of this portfolio is to examine how PostgreSQL executes queries on the VanguardPay database and how to optimise slow queries. I will write SQL queries for core VanguardPay operations, inspect their execution plans using `EXPLAIN ANALYZE`, add targeted indexes, and compare the execution plans and timings before and after indexing.

## How This Builds on Portfolio 1

In Portfolio 1, I designed and built the five relational tables for VanguardPay: `customers`, `accounts`, `transactions`, `transaction_logs`, and `beneficiaries`. In this portfolio, I use that schema to implement and optimise three of the Key Operations from my case study:

| Key Operation | What the query does | Main tables |
|---|---|---|
| **6. Audit account balances** | Compares each account's stored `accounts.balance` against the sum of credits minus debits in `transaction_logs` to flag any discrepancy. | `accounts`, `transaction_logs` |
| **7. Generate account statements** | Returns every ledger entry for a specific customer or account within a chosen date range, ordered chronologically. | `customers`, `accounts`, `transaction_logs`, `transactions` |
| **8. Detect and flag suspicious activity** | Identifies unusually large transfers and accounts executing rapid transfer bursts within a short window. | `transactions`, `accounts` |

I selected these three operations because they filter, join, and aggregate across the largest tables in the database (`transactions` and `transaction_logs`), where performance bottlenecks would appear first on a live payment platform.

## Why I Generated a Larger Dataset First

The test script from Portfolio 1 (`test_constraints.sql`) only inserted a handful of rows to verify my constraints. That small dataset is not suitable for query optimisation testing for two reasons:

1. **PostgreSQL ignores indexes on tiny tables:** When a table only contains a few rows, reading the entire table in a single sequential pass is cheaper than reading an index page plus a table page. The query planner will pick a sequential scan (`Seq Scan`) every time, making it impossible to test whether an index works.
2. **Timings on small tables are too small to compare:** Every query finishes in a fraction of a millisecond, so execution times do not reveal bottlenecks.

To test performance properly, I wrote `seed_large_data.sql` using `generate_series()` to populate the five tables with higher row volumes before running any `EXPLAIN ANALYZE` tests:

| Table | Rows |
|---|---|
| `customers` | 500 |
| `accounts` | 800 |
| `transactions` | 20,000 |
| `transaction_logs` | ~27,500 |
| `beneficiaries` | ~1,400 |

I structured `seed_large_data.sql` around five rules so that my performance tests reflect realistic platform data:

- **Follows all schema constraints:** Account numbers are 10 digits, every transaction satisfies `ck_transactions_type_accounts`, and opening deposits are sized so no running balance ever drops below zero.
- **Maintains ledger consistency:** Every successful or reversed transaction generates matching debit and credit entries in `transaction_logs`, and each account's stored `balance` equals its total credits minus debits. Because of this, my balance audit query (Key Operation 6) returns zero mismatches on a clean run unless I deliberately introduce a discrepancy to test it.
- **Includes varied statuses:** Transactions are distributed across `successful`, `failed`, `pending`, and `reversed`, and accounts include `active`, `frozen`, and `closed` statuses, forcing my queries to filter selectively.
- **Plants suspicious transfer patterns:** About 1% of transactions are high-value transfers, and 10 accounts each execute 20 rapid transfers within a one-hour window so I can test my fraud detection query (Key Operation 8).
- **Refreshes planner statistics:** The script runs `ANALYZE` on all five tables at the end so the PostgreSQL query planner has accurate row-count statistics before I run `EXPLAIN ANALYZE`.
