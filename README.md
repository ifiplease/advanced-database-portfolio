# MIT 8103 Advanced Database Systems Portfolio

**Student:** Anjolaoluwa Adegbite

**Programme:** Master of Information Technology (2026/2027 Academic Session)

**Database system:** PostgreSQL (managed with pgAdmin 4) for Portfolios 1 to 3, and MongoDB Atlas (managed with MongoDB Compass) for Portfolio 4

---

## Selected Case Study: VanguardPay

### Organisation / Scenario

VanguardPay is a simulated fintech company based in Nigeria.

### Nature of the Business / System

VanguardPay is a digital banking and payments platform. Customers sign up through a mobile app or website, open accounts, and move money without visiting a physical branch. The platform lets customers hold balances, send money to other accounts, deposit and withdraw funds, and view their transaction history. Because VanguardPay handles real money, the database must be accurate, secure, and fully auditable. Every naira that moves must be recorded and traceable.

### Users of the Database

- **Customers:** use the app to check balances, make transfers, and view statements.
- **Customer support agents:** look up customer accounts and transactions to resolve complaints.
- **Compliance and audit officers:** review transaction logs and check that account balances are correct.
- **Fraud analysts:** monitor transactions and login activity for suspicious behaviour.
- **Database administrators:** manage the database, backups, performance, and access control.
- **The VanguardPay application backend:** reads and writes data automatically on behalf of customers.

### Major Data to be Stored

**Core Relational Data (PostgreSQL, Portfolios 1, 2, 3 and 5):**

- **Customers:** personal details, contact information, and identity verification (KYC) status.
- **Accounts:** account numbers, account types (e.g. savings, current), balances, currency, and account status.
- **Transactions:** transfers, deposits, and withdrawals, with amounts, timestamps, and status (pending, successful, failed, reversed).
- **Transaction logs:** a permanent audit record of every change to money in the system.
- **Beneficiaries:** saved recipients that customers send money to often.

**Unstructured / Semi-Structured Data (NoSQL, Portfolio 4):**

- **Login sessions and device activity:** records of when and from where customers access the platform.
- **Fraud alerts:** flagged events that need review.

### Key Operations the Database Will Support

1. **Register a customer and open an account.**
2. **Deposit funds** into an account.
3. **Withdraw funds** from an account, blocking the request if the balance is too low.
4. **Transfer funds** between two accounts safely, so that money is never lost or duplicated.
5. **Reverse failed transactions** and put the money back correctly.
6. **Audit account balances** by comparing stored balances against the transaction history.
7. **Generate account statements** for a chosen customer and date range.
8. **Detect and flag suspicious activity**, such as unusually large or very frequent transfers.

### How This Case Study Is Used Across the Portfolio

| Portfolio | How VanguardPay is used |
|---|---|
| [1. Database Design and Modelling](./portfolio-1-database-design/) | ER diagram, 1NF–3NF normalisation, and relational schema for customers, accounts, transactions, logs, and beneficiaries |
| [2. Query Processing and Optimisation](./portfolio-2-query-optimisation/) | Queries on account statements, balance auditing, and suspicious activity, tested on 20,000 transactions with execution plans and indexing |
| [3. Transactions and Concurrency](./portfolio-3-transactions-concurrency/) | Atomic deposits, withdrawals, transfers, and reversals with commit and rollback, row locking against lost updates and deadlocks, and READ COMMITTED against REPEATABLE READ, tested in two pgAdmin 4 sessions |
| [4. NoSQL and Advanced Data Models](./portfolio-4-nosql/) | Login sessions and fraud alerts stored as flexible documents in MongoDB Atlas, with CRUD operations, nested queries, aggregations, indexes, execution plans, and a TTL index, plus a comparison with PostgreSQL `JSONB` |
| 5. Distributed and Cloud Database | Replication, availability, and consistency for a platform that must stay online |

---

## Portfolio Progression

### Portfolio 1: Database Design and Modelling

In Portfolio 1, I designed and implemented the relational database foundation for VanguardPay in PostgreSQL.

- I created the Entity-Relationship Diagram (`er-diagram.png`) and normalised the schema from an unnormalised table through 1NF, 2NF, and 3NF.
- I wrote `schema.sql` to build the five core tables (`customers`, `accounts`, `transactions`, `transaction_logs`, and `beneficiaries`) with surrogate identity keys, `ON DELETE RESTRICT` foreign keys, unique constraints, and named `CHECK` constraints.
- I wrote `test_constraints.sql` to seed sample records and verify in pgAdmin 4 that invalid balances and malformed transactions are rejected.

[View Portfolio 1](./portfolio-1-database-design/)

### Portfolio 2: Query Processing and Optimisation

In Portfolio 2, I tested and optimised Key Operations 6, 7, and 8 (balance auditing, account statements, and suspicious activity detection) on a scaled dataset.

- I wrote `seed_large_data.sql` to populate the tables with 500 customers, 800 accounts, 20,000 transactions, and 27,709 transaction logs.
- I wrote three baseline queries in `queries.sql` and recorded their `EXPLAIN ANALYZE` execution plans in pgAdmin 4 before adding any new indexes.
- I created two targeted indexes in `indexes.sql`: a composite index on `transaction_logs (account_id, logged_at)` for account statements, and a partial covering index on `transactions` for suspicious transfer bursts.
- Account statements (Key Operation 7) dropped from `4.583 ms` to `0.203 ms` (`337` to `57` buffer hits), and suspicious activity detection (Key Operation 8) dropped from `7.624 ms` to `2.790 ms` (`278` to `21` buffer hits). I left the full balance audit (Key Operation 6) unindexed because reading 100% of the log table naturally favours a sequential scan.

[View Portfolio 2](./portfolio-2-query-optimisation/)

### Portfolio 3: Transactions and Concurrency Control
 
In Portfolio 3, I tested how VanguardPay keeps money safe when several steps must succeed together and when several sessions use the same account at the same time. I ran every test on the seeded database from Portfolio 2, using three dedicated test accounts.
 
- I wrote `transactions_atomic.sql` to show `COMMIT`, `ROLLBACK`, and a `ck_accounts_balance` failure cancelling a whole transaction. I built `fn_deposit`, `fn_withdraw`, `fn_transfer`, and `fn_reverse_transaction` (Key Operations 2 to 5) so the balance change, the `transactions` row, and the `transaction_logs` rows succeed or fail as one unit.
- I wrote `concurrency_locking.sql` to run two pgAdmin 4 sessions against the same account. Without locking, two withdrawals of `217260.00` from account C both passed the balance check, and my balance audit showed a difference of `217260.00`. With `SELECT ... FOR UPDATE`, the second withdrawal was refused. I also caused a deadlock between opposite transfers (SQL state `40P01`) and removed it by locking the lower `account_id` first.
- I wrote `isolation_levels.sql` to compare `READ COMMITTED` and `REPEATABLE READ`. The first read account A at `84700.00` and then `85700.00` inside one transaction, while the second held at `85700.00`. A concurrent update under `REPEATABLE READ` failed with SQL state `40001` and succeeded when I retried it.
- I reused the balance audit (Key Operation 6) after every stage, and it found `0` of `800` accounts out of balance each time.

[View Portfolio 3](./portfolio-3-transactions-concurrency/)

### Portfolio 4: NoSQL and Advanced Data Models
 
In Portfolio 4, I moved the semi-structured side of VanguardPay into MongoDB and tested how documents compare with relational tables. I ran everything on a free MongoDB Atlas (M0) cluster through MongoDB Compass and its `mongosh` shell, in a database called `vanguardpay_nosql`, and kept the money ledger in PostgreSQL.
 
- I wrote `seed_documents.js` to build two collections: `login_sessions` (3,000 documents with nested `device` and `geo` objects) and `fraud_alerts` (153 documents whose `rule_payload` changes shape by rule type). I tied them to PostgreSQL through plain `customer_id` and `account_id` values, planted scenarios for test accounts A, B, and C (`account_id` 1 to 3), and loaded the 10 transfer-burst accounts from a pgAdmin query on the Portfolio 2 data (20 transfers each, `33,982,000` NGN in total).
- I wrote `queries_and_indexes.js` to run CRUD operations (`insertOne`, `updateOne` with `$set` and `$push`, `updateMany`, and `deleteMany`), nested queries with dot notation, `$elemMatch`, and `$exists`, and aggregations with `$group` and `$lookup`. The `updateMany` step closed `10` stale low-severity alerts, and the failed-login aggregation showed `358` of `381` failures coming from Nigeria.
- I created five indexes: a compound index on `login_sessions (customer_id, login_at)`, two unique indexes, a TTL index on `expires_at`, and a partial index on open alerts. With `explain('executionStats')`, the customer session query dropped from `3000` documents examined (`SORT > COLLSCAN`, `4 ms`) to `9` (`FETCH > IXSCAN`, `1 ms`), and the open alerts query dropped from `153` to `38`. An expired test session was removed by the TTL index after about `45` seconds.
- I wrote an explanation of suitability comparing MongoDB documents with PostgreSQL tables and `JSONB` for login sessions and polymorphic fraud alerts, and I documented the trade-off that MongoDB has no foreign keys, so the application has to enforce `customer_id` and `account_id` references.

[View Portfolio 4](./portfolio-4-nosql/)

## AI Use Declaration

*(To be completed in the final documentation.)*
