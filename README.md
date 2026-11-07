# VanguardPay - Relational, NoSQL & Distributed Database Architecture

**Database Systems:** PostgreSQL 18 (managed with pgAdmin 4) for Portfolios 1 to 3 and the relational half of Portfolio 5, and MongoDB Atlas (managed with MongoDB Compass) for Portfolios 4 and 5

## Selected Case Study: VanguardPay

### Organisation / Scenario

VanguardPay is a simulated fintech company based in Nigeria.

### Nature of the Business / System

VanguardPay is a digital banking and payments platform. Customers sign up through a mobile app or website, open accounts, and move money without visiting a physical branch. The platform lets customers hold balances, send money to other accounts, deposit and withdraw funds, and view their transaction history. The database must be accurate, secure, and fully auditable. Every transaction and balance change must be recorded and traceable.

### Users of the Database

* **Customers:** use the app to check balances, make transfers, and view statements.

* **Customer support agents:** look up customer accounts and transactions to resolve complaints.

* **Compliance and audit officers:** review transaction logs and check that account balances are correct.

* **Fraud analysts:** monitor transactions and login activity for suspicious behaviour.

* **Database administrators:** manage the database, backups, performance, and access control.

* **The VanguardPay application backend:** reads and writes data automatically on behalf of customers.

### Major Data to be Stored

**Core Relational Data (PostgreSQL, Portfolios 1, 2, 3 and 5):**

* **Customers:** personal details, contact information, and identity verification (KYC) status.

* **Accounts:** account numbers, account types (e.g. savings, current), balances, currency, and account status.

* **Transactions:** transfers, deposits, and withdrawals, with amounts, timestamps, and status (pending, successful, failed, reversed).

* **Transaction logs:** a permanent audit record of every change to money in the system.

* **Beneficiaries:** saved recipients that customers send money to often.

**Unstructured / Semi-Structured Data (NoSQL, Portfolios 4 and 5):**

* **Login sessions and device activity:** records of when and from where customers access the platform.

* **Fraud alerts:** flagged events that need review.

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
| ----- | ----- | 
| [1. Database Design and Modelling](./portfolio-1-database-design/) | ER diagram, 1NF–3NF normalisation, and relational schema for customers, accounts, transactions, logs, and beneficiaries | 
| [2. Query Processing and Optimisation](./portfolio-2-query-optimisation/) | Queries on account statements, balance auditing, and suspicious activity, tested on 20,000 transactions with execution plans and indexing | 
| [3. Transactions and Concurrency](./portfolio-3-transactions-concurrency/) | Atomic deposits, withdrawals, transfers, and reversals with commit and rollback, row locking against lost updates and deadlocks, and READ COMMITTED against REPEATABLE READ, tested in two pgAdmin 4 sessions | 
| [4. NoSQL and Advanced Data Models](./portfolio-4-nosql/) | Login sessions and fraud alerts stored as flexible documents in MongoDB Atlas, with CRUD operations, nested queries, aggregations, indexes, execution plans, and a TTL index, plus a comparison with PostgreSQL `JSONB` | 
| [5. Distributed and Cloud Database](./portfolio-5-distributed-cloud/) | Range partitioning of a `transactions` copy with partition pruning, replication settings, PostgreSQL backup and restore, a 3-node MongoDB Atlas replica set tested with write concern and read preference, a logical JSON backup, and CAP, shard key, and failover design | 

## Portfolio Progression

### Portfolio 1: Database Design and Modelling

In Portfolio 1, I designed and implemented the relational database foundation for VanguardPay in PostgreSQL (PostgreSQL Global Development Group, 2026).

* I created the Entity-Relationship Diagram (`er-diagram.png`) and normalised the schema from an unnormalised table through 1NF, 2NF, and 3NF (Date, 2019; Silberschatz, Korth & Sudarshan, 2019).

* I wrote `schema.sql` to build the five core tables (`customers`, `accounts`, `transactions`, `transaction_logs`, and `beneficiaries`) with surrogate identity keys, `ON DELETE RESTRICT` foreign keys, unique constraints, and named `CHECK` constraints.

* I wrote `test_constraints.sql` to seed sample records and verify in pgAdmin 4 that invalid balances and malformed transactions are rejected.

[View Portfolio 1](./portfolio-1-database-design/)

### Portfolio 2: Query Processing and Optimisation

In Portfolio 2, I tested and optimised Key Operations 6, 7, and 8 (balance auditing, account statements, and suspicious activity detection) on a scaled dataset.

* I wrote `seed_large_data.sql` to populate the tables with 500 customers, 800 accounts, 20,000 transactions, and 27,709 transaction logs.

* I wrote three baseline queries in `queries.sql` and recorded their `EXPLAIN ANALYZE` execution plans in pgAdmin 4 before adding any new indexes (PostgreSQL Global Development Group, 2026).

* I created two targeted indexes in `indexes.sql`: a composite index on `transaction_logs (account_id, logged_at)` for account statements, and a partial covering index on `transactions` for suspicious transfer bursts (Silberschatz, Korth & Sudarshan, 2019).

* Account statements (Key Operation 7) dropped from `4.583 ms` to `0.203 ms` (`337` to `57` buffer hits), and suspicious activity detection (Key Operation 8) dropped from `7.624 ms` to `2.790 ms` (`278` to `21` buffer hits). I left the full balance audit (Key Operation 6) unindexed because reading 100% of the log table naturally favours a sequential scan.

[View Portfolio 2](./portfolio-2-query-optimisation/)

### Portfolio 3: Transactions and Concurrency Control

In Portfolio 3, I tested how VanguardPay keeps money safe when several steps must succeed together and when several sessions use the same account at the same time (Silberschatz, Korth & Sudarshan, 2019). I ran every test on the seeded database from Portfolio 2, using three dedicated test accounts.

* I wrote `transactions_atomic.sql` to show `COMMIT`, `ROLLBACK`, and a `ck_accounts_balance` failure cancelling a whole transaction. I built `fn_deposit`, `fn_withdraw`, `fn_transfer`, and `fn_reverse_transaction` (Key Operations 2 to 5) so the balance change, the `transactions` row, and the `transaction_logs` rows succeed or fail as one unit.

* I wrote `concurrency_locking.sql` to run two pgAdmin 4 sessions against the same account. Without locking, two withdrawals of `217260.00` from account C both passed the balance check, and my balance audit showed a difference of `217260.00`. With `SELECT ... FOR UPDATE`, the second withdrawal was refused. I also caused a deadlock between opposite transfers (SQL state `40P01`) and removed it by locking the lower `account_id` first.

* I wrote `isolation_levels.sql` to compare `READ COMMITTED` and `REPEATABLE READ` (PostgreSQL Global Development Group, 2026). The first read account A at `84700.00` and then `85700.00` inside one transaction, while the second held at `85700.00`. A concurrent update under `REPEATABLE READ` failed with SQL state `40001` and succeeded when I retried it.

* I reused the balance audit (Key Operation 6) after every stage, and it found `0` of `800` accounts out of balance each time.

[View Portfolio 3](./portfolio-3-transactions-concurrency/)

### Portfolio 4: NoSQL and Advanced Data Models

In Portfolio 4, I moved the semi-structured side of VanguardPay into MongoDB and tested how documents compare with relational tables (Kleppmann, 2017; MongoDB, Inc., 2026a). I ran everything on a free MongoDB Atlas (M0) cluster through MongoDB Compass and its `mongosh` shell, in a database called `vanguardpay_nosql`, and kept the money ledger in PostgreSQL.

* I wrote `seed_documents.js` to build two collections: `login_sessions` (3,000 documents with nested `device` and `geo` objects) and `fraud_alerts` (153 documents whose `rule_payload` changes shape by rule type). I linked them to PostgreSQL through `customer_id` and `account_id`, planted scenarios for test accounts A, B, and C (`account_id` 1 to 3), and loaded the 10 transfer-burst accounts from a pgAdmin query on the Portfolio 2 data (20 transfers each, `33,982,000` NGN in total).

* I wrote `queries_and_indexes.js` to run CRUD operations (`insertOne`, `updateOne` with `$set` and `$push`, `updateMany`, and `deleteMany`), nested queries with dot notation, `$elemMatch`, and `$exists`, and aggregations with `$group` and `$lookup` (MongoDB, Inc., 2026a). The `updateMany` step closed `10` stale low-severity alerts, and the failed-login aggregation showed `358` of `381` failures coming from Nigeria.

* I created five indexes: a compound index on `login_sessions (customer_id, login_at)`, two unique indexes, a TTL index on `expires_at`, and a partial index on open alerts. With `explain('executionStats')`, the customer session query dropped from `3,000` documents examined (`SORT > COLLSCAN`, `4 ms`) to `9` (`FETCH > IXSCAN`, `1 ms`), and the open alerts query dropped from `153` to `38`. An expired test session was removed by the TTL index after about `45` seconds.

* I wrote an explanation of suitability comparing MongoDB documents with PostgreSQL tables and `JSONB` for login sessions and polymorphic fraud alerts (Kleppmann, 2017), and I documented the trade-off that MongoDB has no foreign keys, so the application has to enforce `customer_id` and `account_id` references.

[View Portfolio 4](./portfolio-4-nosql/)

### Portfolio 5: Distributed and Cloud Databases

In Portfolio 5, I evaluated VanguardPay as a distributed system across PostgreSQL 18 and the 3-node MongoDB Atlas replica set (Kleppmann, 2017; MongoDB, Inc., 2026b). I implemented and measured range partitioning, replication configuration, backup and restore, write concern and read preference, and I designed the CAP trade-offs, shard keys, and failover for both systems.

* I wrote `partitioning.sql` to build a range-partitioned copy of `transactions` by `created_at` in a separate `partition_demo` schema, so the live ledger and its foreign keys from Portfolios 1 to 3 stayed untouched (PostgreSQL Global Development Group, 2026). The script created 26 monthly partitions from the dates in the data, plus a default partition, and loaded all `20,012` rows with a matching total of `2,969,904,160.00` NGN and `0` rows in the default partition. A one-month query read `1` of `27` partitions and dropped from `4.718 ms` to `0.459 ms` (`282` to `28` buffer hits).

* I wrote `replication_and_backup_checks.sql` to inspect the replication settings of the PostgreSQL 18.6 server: `wal_level` is `replica` with `0` connected standbys and `archive_mode` off, so recovery relies on logical backups. I ran a `pg_dump` Custom-format backup of `vanguardpay_db` and restored it with `pg_restore` into `vanguardpay_restore`. All nine checks matched, including `20,012` transactions, `27,727` transaction logs, and `0` of `800` accounts out of balance.

* I wrote `replica_set_tests.js` to test the Atlas replica set (MongoDB, Inc., 2026b). Inserts under `w: 1`, `"majority"`, and `w: 3` averaged `105.6`, `109.4`, and `115.8` ms, and a `w: 4` write was rejected with `UnsatisfiableWriteConcern` (code `100`) but its document was still stored. A `secondary` read was answered by a different node from the `primary`, `secondaryPreferred` reads split `5` and `5` across the two secondaries, and `0` of `20` immediate secondary reads missed a fresh write.

* I exported the `153` documents of `fraud_alerts` as Extended JSON and imported them into `fraud_alerts_restore_test`. The counts, the `created_at` date types, and the totals by rule type all matched.

* I documented the CAP trade-offs (Brewer, 2000; Gilbert & Lynch, 2002): consistency for the ledger and `w: "majority"` fraud alert writes, and eventual consistency for `secondaryPreferred` analytics reads. I designed a synchronous standby quorum for PostgreSQL, proposed shard keys of `{ customer_id: 1, login_at: 1 }` for `login_sessions` and `{ customer_id: 1, created_at: 1 }` for `fraud_alerts`, and compared failover for both systems.

[View Portfolio 5](./portfolio-5-distributed-cloud/)

## Technical Reflection

### Key Insights, Challenges, and Design Trade-offs

* **Database-Level Integrity vs. Seeding Complexity:** Enforcing `ON DELETE RESTRICT` foreign keys and named `CHECK` constraints (`ck_transactions_type_accounts`, `ck_accounts_balance`) ensures the database rejects invalid states directly rather than relying on application validation (Date, 2019). In Portfolio 2, this strictness required sizing opening deposits carefully in `seed_large_data.sql` so that sequential transfers never drove running balances below zero.
* **Targeted Indexing vs. Write Overhead:** The composite and partial covering indexes reduced account statement queries from `4.583 ms` to `0.203 ms` and suspicious transfer burst detection from `7.624 ms` to `2.790 ms`, whereas the full balance audit was left unindexed because reading 100% of the log table favours a sequential scan. Because every index adds write overhead to an insert-heavy ledger, only those two indexes were added (PostgreSQL Global Development Group, 2026).
* **Concurrency Correctness vs. Blocking Latency:** Without row locking, two concurrent withdrawals of `217260.00` from account C both passed the balance check and created a `217260.00` ledger discrepancy. Introducing `SELECT ... FOR UPDATE` serialized the conflicting reads, locking accounts in ascending `account_id` order prevented `40P01` deadlocks, and `REPEATABLE READ` serialization failures (`40001`) demonstrated where application retry logic is required (Silberschatz, Korth & Sudarshan, 2019).
* **Schema Flexibility vs. Referential Integrity:** Polymorphic `rule_payload` structures fit MongoDB documents cleanly without sparse nullable columns, and the compound index reduced customer session queries from `3,000` documents examined to `9`. Because MongoDB does not enforce foreign keys across collections or databases, `customer_id` and `account_id` integrity must be enforced by the application layer, while core monetary balances remain in PostgreSQL (Kleppmann, 2017; MongoDB, Inc., 2026a).
* **Distributed Write Guarantees vs. Rollback Semantics:** Rejecting the `{ w: 4 }` write with `UnsatisfiableWriteConcern` (code `100`) still left the inserted document on the primary node, demonstrating that a write-concern error does not roll back the write the way a PostgreSQL transaction does. Choosing strong consistency for the ledger and `w: "majority"` fraud alert writes while allowing eventual consistency on `secondaryPreferred` analytics reads balances correctness and read scalability across the two systems (Brewer, 2000; Gilbert & Lynch, 2002; MongoDB, Inc., 2026b).

## AI Use Declaration

This declaration covers Portfolios 1 to 5.

**AI tool used:** Claude (Anthropic).

**What I used it for:** I used Claude as a learning partner. It clarified database concepts, assisted with SQL and `mongosh` scripting and troubleshooting, and helped draft the documentation.

**How I reviewed, corrected, tested and verified the output:** I ran every SQL script in pgAdmin 4 and every `mongosh` script in MongoDB Compass myself, and I took all screenshots from my own runs. I copied every figure in the portfolio READMEs from my own output. I checked results against expected values, for example constraint rejections, plan comparisons before and after indexing, concurrency tests reproduced in two pgAdmin 4 sessions, and restored copies that matched the originals. I used the balance audit across the portfolios to confirm that `0` of `800` accounts were out of balance.

I remain responsible for the accuracy, originality and understanding of everything in this portfolio.

## References

* Brewer, E. (2000). *Towards Robust Distributed Systems.* Keynote, ACM Symposium on Principles of Distributed Computing.
* Date, C. J. (2019). *Database Design and Relational Theory: Normal Forms and All That Jazz* (2nd ed.). Apress.
* Gilbert, S., & Lynch, N. (2002). Brewer's conjecture and the feasibility of consistent, available, partition-tolerant web services. *ACM SIGACT News*, 33(2), 51–59.
* Kleppmann, M. (2017). *Designing Data-Intensive Applications.* O'Reilly Media.
* MongoDB, Inc. (2026a). *MongoDB Manual (Version 8.0): CRUD, Aggregation Pipeline, Indexes, Replication, and Sharding.* https://www.mongodb.com/docs/manual/
* MongoDB, Inc. (2026b). *MongoDB Atlas Documentation.* https://www.mongodb.com/docs/atlas/
* PostgreSQL Global Development Group. (2026). *PostgreSQL 18 Documentation: SQL Language, Performance Tips, Concurrency Control, Table Partitioning, and High Availability.* https://www.postgresql.org/docs/18/
* Silberschatz, A., Korth, H. F., & Sudarshan, S. (2019). *Database System Concepts* (7th ed.). McGraw-Hill.
