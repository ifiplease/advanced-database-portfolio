# Portfolio 4: NoSQL and Advanced Data Models

**Case study:** VanguardPay 

**Database system:** MongoDB Atlas (M0 free tier), managed with MongoDB Compass and its built-in `mongosh` shell

---

## Overview

In this portfolio, I moved the semi-structured side of VanguardPay into MongoDB. I designed two collections for data that does not fit neatly into rows and columns: login sessions with device activity, and fraud alerts whose rule details change from one alert type to the next. I kept the money ledger in PostgreSQL (Portfolios 1 to 3) and linked the two systems through `customer_id` and `account_id`.

I wrote two scripts and ran them in the Compass `mongosh` shell:

- `seed_documents.js` builds and seeds both collections.
- `queries_and_indexes.js` runs the CRUD operations, nested queries, aggregations, indexes, `explain` comparisons, and a TTL demonstration, one numbered section at a time.

### How I ran it

1. I created a free MongoDB Atlas M0 cluster, a database user, and an IP access list entry, then connected MongoDB Compass with the Atlas connection string. I kept the connection string and password out of the repository and the screenshots.
2. I ran a query in pgAdmin 4 on the Portfolio 2 data to pull the real transfer-burst summaries for accounts 1 to 10 (shown below), and pasted the JSON result into the `burstData` line of `seed_documents.js`.
3. I pasted `seed_documents.js` into the Compass `mongosh` shell. The script stops unless `burstData` holds exactly 10 objects, then drops and rebuilds both collections.
4. I ran `queries_and_indexes.js` one numbered section at a time and captured the evidence in `screenshots/`.

The pgAdmin query that supplies the burst data:

```sql
-- Portfolio 4: burst summaries for the MongoDB seed
WITH big_transfers AS (
    SELECT source_account_id AS account_id, created_at, amount
    FROM transactions
    WHERE transaction_type = 'transfer'
      AND status = 'successful'
      AND amount >= 50000
      AND source_account_id BETWEEN 1 AND 10
),
burst_rows AS (
    SELECT b.*
    FROM big_transfers b
    WHERE (SELECT count(*)
           FROM big_transfers x
           WHERE x.account_id = b.account_id
             AND x.created_at BETWEEN b.created_at - interval '1 hour'
                                  AND b.created_at + interval '1 hour') >= 10
)
SELECT json_agg(row_to_json(s) ORDER BY s.account_id) AS burst_json
FROM (
    SELECT account_id,
           count(*)        AS transfer_count,
           sum(amount)     AS total_amount,
           min(created_at) AS first_transfer_at,
           max(created_at) AS last_transfer_at
    FROM burst_rows
    GROUP BY account_id
) s;
```

It returned 10 objects, one per account. Each shows 20 transfers inside a 57-minute window, and the ten totals add up to `33,982,000.00` NGN across 200 transfers.

---

## Stage 1: Data Model and Seeding

### Collections

I created two collections in vanguardpay_nosql.

**`login_sessions`** holds one document per login attempt.

| Field | Type | Notes |
|---|---|---|
| `session_id` | string | Unique, for example `SES000001` |
| `customer_id` | number | Refers to PostgreSQL `customers.customer_id` |
| `ip_address` | string | Address used for the login |
| `device` | embedded object | Mobile: `type`, `device_id`, `os`, `os_version`, `model`, `app_version`. Web: `type`, `device_id`, `os`, `browser`, `browser_version` |
| `geo` | embedded object | `country`, `city`, `latitude`, `longitude` |
| `outcome` | string | `success`, `failed`, or `blocked` |
| `session_token_hash` | string | Successful logins only. I store a 64-character hash, never the raw token |
| `failure_reason` | string | Failed or blocked logins only |
| `login_at` | date | When the login happened |
| `expires_at` | date | 90 days after `login_at`. The TTL index reads this field |

**`fraud_alerts`** holds one document per flagged event.

| Field | Type | Notes |
|---|---|---|
| `alert_id` | string | Unique, for example `FRD00001` |
| `customer_id` | number | Refers to PostgreSQL `customers.customer_id` |
| `account_id` | number | Refers to PostgreSQL `accounts.account_id` |
| `rule_type` | string | `transfer_burst`, `impossible_travel`, `device_mismatch`, or `failed_login_streak` |
| `severity` | string | `low`, `medium`, `high`, or `critical` |
| `status` | string | `open`, `under_review`, `confirmed_fraud`, or `false_positive` |
| `rule_payload` | embedded object | The shape changes with `rule_type` (see below) |
| `session_ids` | array of strings | Matching `login_sessions.session_id` values. Not present on `transfer_burst` alerts |
| `review_notes` | array of objects | Each note has `analyst`, `note`, and `noted_at` |
| `created_at` | date | When the alert was raised |
| `resolved_at` | date | Only on `confirmed_fraud` and `false_positive` alerts |

The `rule_payload` object is where the document model matters most. Each rule type stores different fields:

| `rule_type` | Fields in `rule_payload` |
|---|---|
| `transfer_burst` | `transfer_count`, `total_amount`, `currency`, `min_amount`, `first_transfer_at`, `last_transfer_at`, `window_minutes` |
| `impossible_travel` | `from_city`, `to_city`, `distance_km`, `minutes_between`, `implied_speed_kmh`, `max_allowed_kmh` |
| `device_mismatch` | `known_device_id`, `seen_device_id`, `new_device_first_seen`, plus device details such as `seen_device_model` or `seen_device_type` |
| `failed_login_streak` | `failed_attempts`, `window_minutes`, `ended_in`, `ip_address` |

Two alerts for `account_id` 1, trimmed for space (`_id` and some fields omitted, dates shown as text):

```json
{
  "alert_id": "FRD00001",
  "customer_id": 1,
  "account_id": 1,
  "rule_type": "impossible_travel",
  "severity": "critical",
  "status": "open",
  "rule_payload": {
    "from_city": "Lagos",
    "to_city": "London",
    "distance_km": 5020,
    "minutes_between": 20,
    "implied_speed_kmh": 15060,
    "max_allowed_kmh": 900
  },
  "session_ids": ["SES000001", "SES000002"],
  "review_notes": []
}
```

```json
{
  "alert_id": "FRD00004",
  "customer_id": 1,
  "account_id": 1,
  "rule_type": "transfer_burst",
  "severity": "high",
  "status": "open",
  "rule_payload": {
    "transfer_count": 20,
    "total_amount": 3240000,
    "currency": "NGN",
    "min_amount": 50000,
    "first_transfer_at": "2026-10-09T00:34:03+01:00",
    "last_transfer_at": "2026-10-09T01:31:03+01:00",
    "window_minutes": 57
  },
  "review_notes": [],
  "created_at": "2026-10-09T01:36:03+01:00"
}
```

### How the documents connect to PostgreSQL

| MongoDB field | PostgreSQL source | How I tied them together |
|---|---|---|
| `customer_id` (both collections) | `customers.customer_id`, 1 to 500 | Plain number copied from the seeded data |
| `account_id` (`fraud_alerts`) | `accounts.account_id` | Plain number. Burst alerts use accounts 1 to 10, and random alerts use the customer's first account, where `account_id` equals `customer_id` |
| `transfer_burst` payload values | `transactions` rows seeded in Portfolio 2 | Real counts, totals, and timestamps from the pgAdmin query above |
| Test accounts A, B, C | `account_id` 1, 2, 3 (customers 1, 2, 3) from Portfolio 3 | Planted scenarios (below) |

### What `seed_documents.js` creates

- **3,000 sessions:** 12 planted sessions for customers 1 to 3, and random sessions for customers 4 to 500 spread over the last 30 days. About 85% succeed, 12% fail, and 3% are blocked, and about 5% come from outside Nigeria.
- **153 alerts:** 3 planted alerts for the test accounts, 10 `transfer_burst` alerts from the pgAdmin results, and 140 random alerts for customers 4 to 500.
- **TTL safety:** every `expires_at` is 90 days after the login, so no seeded session expires while I work.

| Test account | Customer | Planted scenario | Alert |
|---|---|---|---|
| A (`account_id` 1) | 1 | Login from Lagos, then from London 20 minutes later on a different device | `impossible_travel`, `critical`, `open` |
| B (`account_id` 2) | 2 | Three logins on a known iPhone, then a login from a new Android phone in Abuja | `device_mismatch`, `medium`, `under_review` with one analyst note |
| C (`account_id` 3) | 3 | Five failed logins in five minutes, then a successful login | `failed_login_streak`, `medium`, `open` |

Accounts 1 to 3 are also in the burst set, so each has a `transfer_burst` alert as well.

![Compass showing the vanguardpay_nosql database with its two collections](screenshots/compass-collections-overview.png)

*Figure 1: The `vanguardpay_nosql` database in Compass, showing `login_sessions` and `fraud_alerts` with their document counts.*

![A login_sessions document with nested device and geo objects](screenshots/compass-login-session-document.png)

*Figure 2: One `login_sessions` document with the nested `device` and `geo` objects.*

![Two fraud_alerts documents with different rule_payload shapes](screenshots/compass-fraud-alert-payloads.png)

*Figure 3: The `impossible_travel` and `transfer_burst` alerts for `account_id` 1, with two different `rule_payload` shapes in the same collection.*

---

## Stage 2: Queries, Aggregations and Indexes

### CRUD operations

I ran the four CRUD operations on `fraud_alerts` in sections 1 to 4 of `queries_and_indexes.js`:

- **Create:** `insertOne` added a manual alert (`FRD99001`) for `account_id` 2 with a new `rule_type` of `manual_flag` and a payload shape no other alert has. The collection accepted it with no schema change.
- **Update one:** `updateOne` used `$set` to change `status` to `under_review` and `severity` to `medium`, and `$push` to add an analyst note to `review_notes`. I read the document back to confirm both changes.
- **Update many:** `updateMany` moved every low-severity `open` alert older than 14 days to `false_positive` and stamped `resolved_at` with `$currentDate`. It matched and modified 10 documents (`matchedCount: 10`, `modifiedCount: 10`).
- **Delete:** `deleteMany` removed the `manual_flag` alert, and `countDocuments()` returned 153 again.

![Update result and the alert read back with its pushed review note](screenshots/compass-crud-update-result.png)

*Figure 4: `updateOne` with `$set` and `$push`, followed by the alert read back with the new note in `review_notes`.*

### Nested queries

In section 5, I ran three queries that reach inside nested objects and arrays:

- **Dot notation:** `outcome: 'success'`, `'device.type': 'mobile'`, and `'geo.country': { $ne: 'NG' }` found successful mobile logins from outside Nigeria, with a projection of `device.model` and `geo.city`.
- **`$elemMatch`:** `review_notes: { $elemMatch: { analyst: 'ada.obi', note: /customer/i } }` found alerts where one single note was written by that analyst and mentions the customer. `$elemMatch` makes both conditions apply to the same array item.
- **`$exists` on payload fields:** `'rule_payload.implied_speed_kmh': { $exists: true, $gte: 15000 }` found alerts that carry an implied speed field, which only `impossible_travel` payloads have.

![Nested query results using dot notation and elemMatch](screenshots/compass-nested-query-result.png)

*Figure 5: Nested queries on `review_notes` with `$elemMatch` and on payload fields with `$exists`.*

### Aggregations

In section 6, I ran four aggregation pipelines.

**6a. Failed logins per country** (`$match`, `$group`, `$sort` on `login_sessions`):

| Country | Failed logins |
|---|---|
| NG | 358 |
| GH | 10 |
| GB | 9 |
| AE | 4 |

About 94% of the 381 failed logins come from Nigeria, so the few foreign failures stand out.

**6b. Alerts by rule type and severity** (`$group` on a two-field `_id`):

| Rule type | Severity | Alerts |
|---|---|---|
| `device_mismatch` | low | 25 |
| `device_mismatch` | medium | 18 |
| `failed_login_streak` | high | 25 |
| `failed_login_streak` | medium | 23 |
| `impossible_travel` | critical | 22 |
| `impossible_travel` | high | 30 |
| `transfer_burst` | high | 10 |

The groups add up to the 153 alerts in the collection.

**6c. Transfer burst totals.** I summed `rule_payload.transfer_count` and `rule_payload.total_amount` across the 10 `transfer_burst` alerts to cross-check MongoDB against PostgreSQL. The ten pgAdmin burst totals add up to `33,982,000.00` NGN over 200 transfers, so the MongoDB aggregation should match it exactly.

**6d. `$lookup` join.** I joined the `impossible_travel` alert for `account_id` 1 to `login_sessions` through `session_ids` and `session_id`. The result shows the Lagos and London logins inside the alert, 20 minutes apart. This is MongoDB's version of a SQL join, and it runs at query time with no foreign key behind it.

![Burst total aggregation and the lookup join between alerts and sessions](screenshots/compass-aggregation-result.png)

*Figure 6: The transfer burst totals (6c) and the `$lookup` join from an alert to its login sessions (6d).*

### Indexes

In sections 8, I created five indexes:

| Index | Collection | Type | Keys | Purpose |
|---|---|---|---|---|
| `idx_sessions_customer_login_at` | `login_sessions` | Compound | `customer_id` ascending, `login_at` descending | A customer's login history, newest first |
| `uq_sessions_session_id` | `login_sessions` | Unique | `session_id` | One document per session, and a fast target for `$lookup` |
| `ttl_sessions_expires_at` | `login_sessions` | TTL (`expireAfterSeconds: 0`) | `expires_at` | Removes sessions automatically after they expire |
| `uq_alerts_alert_id` | `fraud_alerts` | Unique | `alert_id` | One document per alert, and fast lookups for updates |
| `idx_alerts_open_severity_created` | `fraud_alerts` | Partial (`status: 'open'`) | `severity` ascending, `created_at` descending | Open alerts by severity, newest first |

### Execution plans with `explain('executionStats')`

I used a small helper, `explainSummary`, to print the key figures from `explain('executionStats')`, the same way I recorded `EXPLAIN ANALYZE` in Portfolio 2. I ran the same two queries before and after creating the indexes:

| Query | Stage | Plan | Documents examined | Keys examined | Documents returned | Time (ms) |
|---|---|---|---|---|---|---|
| Sessions for one customer, newest first | Before | `SORT > COLLSCAN` | 3,000 | 0 | 9 | 4 |
| Sessions for one customer, newest first | After | `FETCH > IXSCAN` | 9 | 9 | 9 | 1 |
| Open high-severity alerts, newest first | Before | `SORT > COLLSCAN` | 153 | 0 | 38 | 0 |
| Open high-severity alerts, newest first | After | `FETCH > IXSCAN` | 38 | 38 | 38 | 0 |

The session query went from reading all 3,000 documents to reading only the 9 that match, about 99.7% fewer, and the `SORT` stage disappeared because the compound index already stores each customer's logins newest first. The alert query dropped from 153 documents examined to 38, about 75% fewer. Its time stayed at 0 ms because the collection is small, so the evidence is the amount of work saved, not the clock.

![Explain output before indexing showing COLLSCAN plans](screenshots/compass-explain-before-index.png)

*Figure 7: `explain` summaries before indexing. Both queries use `SORT > COLLSCAN` and read every document.*

![Explain output after indexing showing IXSCAN plans](screenshots/compass-explain-after-index.png)

*Figure 8: `explain` summaries after indexing. Both queries use `FETCH > IXSCAN` and examine only matching documents.*

### TTL index demonstration

In section 10, I inserted a session whose `expires_at` was one minute in the past. The count right after the insert was 1. MongoDB's background TTL task removed it after about 45 seconds, and `login_sessions` was back to 3,000 documents. Deletion is not instant, because the TTL task wakes up roughly once a minute.

![TTL demo showing the expired session count and its removal](screenshots/compass-ttl-index-demo.png)

*Figure 9: The expired test session counted as 1 straight after insertion, then removed by the TTL index after about 45 seconds.*

---

## Explanation of Suitability

### Why documents fit login sessions

A login session is one self-contained event. The device and location only matter in the context of that login, so I embedded `device` and `geo` inside each session. One read returns everything an analyst needs, with no join. The shapes also differ between records:

- Mobile devices carry `model`, `os_version`, and `app_version`, while web devices carry `browser` and `browser_version`.
- Successful logins carry `session_token_hash`, while failed and blocked logins carry `failure_reason`.

In a relational design, I would need nullable columns for every variation, or separate tables for devices and locations joined back to each login. Sessions are also written constantly and rarely updated, and they expire. The TTL index on `expires_at` handles that cleanup inside the database. PostgreSQL has no built-in equivalent, so I would need a scheduled job to delete old rows.

### Why documents fit polymorphic fraud alerts

Each fraud rule produces a different payload. A transfer burst records counts and totals, impossible travel records cities and speed, and a device mismatch records device identifiers. In one PostgreSQL table, that means a wide table full of nulls, a table per rule type, or a generic key-value layout that is hard to query. In MongoDB, each alert holds exactly the fields its rule produces. Adding the `manual_flag` alert in section 1 needed no `ALTER TABLE` and no migration. The analyst `review_notes` also sit inside the alert as an array, where a relational design would use a child table with its own key and join.

### MongoDB, PostgreSQL tables and PostgreSQL `JSONB` compared

| Criterion | MongoDB documents | PostgreSQL relational tables | PostgreSQL `JSONB` |
|---|---|---|---|
| Flexible shape | Each document can have its own fields, with no schema change | Fixed columns, so variations need nulls or extra tables | Flexible inside the `JSONB` column, while the other columns stay fixed |
| Nested data | Stored natively and queried with dot notation | Needs child tables and joins | Stored natively in the column and queried with `->` and `->>` |
| Updating one nested value | `$set` and `$push` change a single field or array item | `UPDATE` or `INSERT` on the relevant table or child table | Rewrites the `JSONB` value, which writes a new version of the whole row |
| Referential integrity | None across collections or databases, so the application must enforce it | Foreign keys, `CHECK` constraints, and `ON DELETE RESTRICT` | Foreign keys on ordinary columns such as `customer_id`, but none for keys inside the `JSONB` |
| Joins | `$lookup` at query time | Standard SQL `JOIN` | Standard SQL `JOIN` to other tables |
| Automatic expiry | Built-in TTL index | None built in, so a scheduled delete job is needed | None built in, so a scheduled delete job is needed |
| Indexing nested fields | Index on a dot-notation path, such as `device.type` | B-tree on ordinary columns | GIN index on the `JSONB` column |
| Fit for VanguardPay | Best for sessions and alerts | Best for money, balances, and the ledger | A reasonable choice if I wanted one database for everything |

While PostgreSQL JSONB could store flexible payloads inside the existing relational engine, deploying MongoDB Atlas provides native document-level atomic modifiers ($push), built-in TTL collection expiration, and an out-of-the-box multi-node replica set for distributed cloud workloads.

### Why the money ledger stays in PostgreSQL

Balances, transfers, and reversals depend on enforced rules: `CHECK (balance >= 0)`, foreign keys, and the row locking I tested in Portfolio 3. MongoDB does support multi-document transactions, but the relational constraints in Portfolio 1 protect money better. The two systems also fit the work differently. PostgreSQL holds what must always be exactly right, and MongoDB holds records that are flexible and short-lived.

### Trade-off: application-level foreign keys

MongoDB has no foreign keys. My `customer_id` and `account_id` fields are plain numbers, and nothing stops me from inserting an alert for an account that does not exist in PostgreSQL. In Portfolio 1, I used `ON DELETE RESTRICT` so a customer with accounts could not be deleted. Here, deleting a customer in PostgreSQL would leave orphaned sessions and alerts in MongoDB. The same applies inside MongoDB: `session_ids` in an alert point to `login_sessions.session_id`, and `$lookup` only joins at query time. The application layer would have to:

- check that `customer_id` and `account_id` exist in PostgreSQL before inserting a document;
- clean up or archive related documents when a customer is closed;
- run periodic checks for orphaned documents, in the same spirit as the balance audit I built in Portfolio 3.

In this portfolio, cross-database referential consistency was maintained deterministically by seeding customer_id (1 to 500), account_id (1 to 10), and transfer-burst aggregates directly from the PostgreSQL dataset.

---

## Technical Reflection

### Key Insights and Trade-offs

- **Embedding vs. Referencing:** Embedding `device`, `geo`, and `review_notes` inside their parent documents enables single-read retrieval without joins. The trade-off is controlled denormalisation (repeating device metadata across sessions) compared to 3NF relational tables.
- **Schema Polymorphism vs. Structural Enforcement:** Storing rule-specific fields inside `rule_payload` allowed four distinct fraud alert structures (plus the ad-hoc `manual_flag` alert) to coexist without `ALTER TABLE` migrations or sparse `NULL` columns. Conversely, the absence of a fixed relational schema requires application-level validation to prevent field-name typos.
- **Application-Level Referential Integrity:** Because MongoDB does not enforce cross-database foreign keys against PostgreSQL (`customer_id` and `account_id`) or across collections (`session_ids`), referential integrity and orphan prevention shift to the application service layer. Core monetary balances and double-entry ledgers therefore remain in PostgreSQL.
- **Compound and Partial Indexing:** The compound index `idx_sessions_customer_login_at` satisfied both the equality filter (`customer_id`) and the sort order (`login_at: -1`), reducing documents examined from `3,000` to `9` (`99.7%` reduction) and eliminating the in-memory `SORT` stage. The partial index `idx_alerts_open_severity_created` indexed only `status: 'open'` documents, cutting examined documents from `153` to `38` while minimising index storage overhead.
- **Asynchronous TTL Retention:** The TTL index on `expires_at` (`expireAfterSeconds: 0`) purged the expired test session automatically after `45 seconds`. Because MongoDB's background TTL thread runs once per minute, TTL indexes are ideal for storage retention hygiene rather than millisecond-exact session revocation.

---

## AI Use Declaration

- **AI tool used:** Claude (Anthropic).
- **What I used it for:** I used Claude as a learning partner to design the polymorphic document structures for `login_sessions` and `fraud_alerts`, draft the `mongosh` seeding and aggregation scripts, and structure the suitability comparison between MongoDB documents, PostgreSQL relational tables, and `JSONB`.
- **How I reviewed and verified it:** All `mongosh` scripts were manually executed and verified against a live MongoDB Atlas cluster using MongoDB Compass. Transfer-burst summaries (`200` transfers totalling `33,982,000.00 NGN`) were extracted directly from the Portfolio 2 PostgreSQL database to ensure cross-database consistency, and all execution plan metrics (`COLLSCAN` vs. `IXSCAN`), aggregation counts, and TTL expiration timings were recorded from empirical outputs..

---

## References

- MongoDB Inc. (2026). *MongoDB Manual*. https://www.mongodb.com/docs/manual/
- MongoDB Inc. (2026). *MongoDB Atlas documentation*. https://www.mongodb.com/docs/atlas/
- MongoDB Inc. (2026). *MongoDB Compass documentation*. https://www.mongodb.com/docs/compass/
- MongoDB Inc. (2026). *MongoDB Shell (`mongosh`) documentation*. https://www.mongodb.com/docs/mongodb-shell/
- MongoDB Inc. (2026). *Aggregation pipeline*. https://www.mongodb.com/docs/manual/core/aggregation-pipeline/
- MongoDB Inc. (2026). *`$lookup` (aggregation)*. https://www.mongodb.com/docs/manual/reference/operator/aggregation/lookup/
- MongoDB Inc. (2026). *`$elemMatch` (query)*. https://www.mongodb.com/docs/manual/reference/operator/query/elemMatch/
- MongoDB Inc. (2026). *TTL indexes*. https://www.mongodb.com/docs/manual/core/index-ttl/
- MongoDB Inc. (2026). *Partial indexes*. https://www.mongodb.com/docs/manual/core/index-partial/
- MongoDB Inc. (2026). *Explain results*. https://www.mongodb.com/docs/manual/reference/explain-results/
- MongoDB Inc. (2026). *Transactions*. https://www.mongodb.com/docs/manual/core/transactions/
- PostgreSQL Global Development Group. (2026). *JSON types*. https://www.postgresql.org/docs/current/datatype-json.html
- PostgreSQL Global Development Group. (2026). *GIN indexes*. https://www.postgresql.org/docs/current/gin.html
- School of Post Graduate Studies. (2026). *MIT 8103 Advanced Database Systems: First Semester Continuous Assessment, 2026/2027 Academic Session*. Course brief.
- Anthropic. (2026). *Claude* [AI assistant]. Used as declared in the AI Use Declaration above.
