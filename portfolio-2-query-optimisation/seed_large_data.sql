-- MIT 8103 Advanced Database Systems
-- Portfolio 2: Large seed data for VanguardPay (run schema.sql first)

-- 1. Clear old data and drop leftover staging tables
TRUNCATE TABLE beneficiaries, transaction_logs, transactions, accounts, customers
    RESTART IDENTITY CASCADE;
DROP TABLE IF EXISTS stg_event;
DROP TABLE IF EXISTS stg_txn;
DROP TABLE IF EXISTS stg_active_accounts;

-- 2. Customers (500)
WITH base AS MATERIALIZED (
    SELECT i,
           (ARRAY['Adebayo','Chioma','Ibrahim','Funke','Emeka','Aisha','Tunde','Ngozi',
                  'Segun','Zainab','Chidi','Bukola','Musa','Folake','Obinna','Hauwa',
                  'Kunle','Amaka','Yusuf','Temitope'])[1 + floor(random() * 20)::int] AS first_name,
           (ARRAY['Adeyemi','Okafor','Bello','Balogun','Eze','Abubakar','Ogunleye','Nwosu',
                  'Lawal','Okonkwo','Adeleke','Umar','Olawale','Chukwu','Sanni','Afolabi',
                  'Ibe','Danjuma','Akinola','Onyeama'])[1 + floor(random() * 20)::int] AS last_name,
           random() AS r_kyc,
           random() AS r_dob,
           random() AS r_created
    FROM generate_series(1, 500) AS i
)
INSERT INTO customers (first_name, last_name, email, phone_number, date_of_birth, kyc_status, created_at)
SELECT first_name,
       last_name,
       lower(first_name || '.' || last_name || i || '@example.com'),
       (ARRAY['0803','0805','0807','0810','0813','0816','0703','0706','0802','0809'])[1 + i % 10]
           || lpad(i::text, 7, '0'),
       DATE '1960-01-01' + floor(r_dob * 17000)::int,
       CASE WHEN r_kyc < 0.90 THEN 'verified'
            WHEN r_kyc < 0.98 THEN 'pending'
            ELSE 'rejected' END,
       now() - interval '300 days' - r_created * interval '430 days'
FROM base
ORDER BY i;

-- 3. Accounts (800, customers 1 to 300 hold two accounts each)
INSERT INTO accounts (customer_id, account_number, account_type, balance, currency, status, opened_at)
SELECT c.customer_id,
       '30' || lpad(i::text, 8, '0'),
       CASE WHEN random() < 0.65 THEN 'savings' ELSE 'current' END,
       0,
       'NGN',
       CASE WHEN i % 50 = 0 THEN 'closed'
            WHEN i % 20 = 0 THEN 'frozen'
            ELSE 'active' END,
       c.created_at + random() * interval '30 days'
FROM generate_series(1, 800) AS i
JOIN customers c ON c.customer_id = ((i - 1) % 500) + 1
ORDER BY i;

-- 4. Staging: active accounts numbered 1..n so random picks are easy
CREATE TEMP TABLE stg_active_accounts AS
SELECT account_id, row_number() OVER (ORDER BY account_id)::int AS rn
FROM accounts
WHERE status = 'active';

CREATE TEMP TABLE stg_txn (
    n                      INT PRIMARY KEY,
    reference              VARCHAR(30),
    transaction_type       VARCHAR(20),
    source_account_id      BIGINT,
    destination_account_id BIGINT,
    amount                 NUMERIC(15,2),
    status                 VARCHAR(20),
    created_at             TIMESTAMPTZ,
    r_rev                  DOUBLE PRECISION DEFAULT random()
);

-- 5. Staging: everyday transactions (deposits, withdrawals, transfers)
INSERT INTO stg_txn (n, transaction_type, source_account_id, destination_account_id, amount, status, created_at)
WITH base AS MATERIALIZED (
    SELECT n,
           random() AS r_type, random() AS r_src, random() AS r_dst, random() AS r_amt,
           random() AS r_big,  random() AS r_stat, random() AS r_time,
           (SELECT count(*) FROM stg_active_accounts)::int AS cnt
    FROM generate_series(1, (20000 - 200 - (SELECT count(*) FROM accounts WHERE status <> 'closed'))::int) AS n
),
picked AS (
    SELECT n, r_type, r_amt, r_big, r_stat, r_time, cnt,
           1 + floor(r_src * cnt)::int AS src_rn,
           1 + floor(r_dst * cnt)::int AS dst_rn
    FROM base
),
typed AS (
    SELECT n, r_amt, r_big, r_stat, r_time, src_rn,
           CASE WHEN dst_rn = src_rn THEN (src_rn % cnt) + 1 ELSE dst_rn END AS dst_rn,
           CASE WHEN r_type < 0.30 THEN 'deposit'
                WHEN r_type < 0.55 THEN 'withdrawal'
                ELSE 'transfer' END AS transaction_type
    FROM picked
)
SELECT t.n,
       t.transaction_type,
       CASE WHEN t.transaction_type <> 'deposit' THEN s.account_id END,
       CASE WHEN t.transaction_type <> 'withdrawal' THEN d.account_id END,
       CASE WHEN t.r_big < 0.01 THEN round((2000000 + t.r_amt * 3000000)::numeric, -3)
            ELSE round(exp(7 + 6 * t.r_amt)::numeric, -2) END,
       CASE WHEN t.r_stat < 0.90 THEN 'successful'
            WHEN t.r_stat < 0.95 THEN 'failed'
            WHEN t.r_stat < 0.97 THEN 'pending'
            ELSE 'reversed' END,
       date_trunc('second', now() - interval '240 days'
                  + t.r_time * (interval '240 days' - interval '2 hours'))
FROM typed t
JOIN stg_active_accounts s ON s.rn = t.src_rn
JOIN stg_active_accounts d ON d.rn = t.dst_rn;

-- 6. Staging: suspicious bursts (10 accounts, 20 rapid large transfers each)
INSERT INTO stg_txn (n, transaction_type, source_account_id, destination_account_id, amount, status, created_at)
WITH base AS MATERIALIZED (
    SELECT 100000 + i AS n, i,
           random() AS r_dst, random() AS r_amt,
           (SELECT count(*) FROM stg_active_accounts)::int AS cnt
    FROM generate_series(1, 200) AS i
)
SELECT b.n,
       'transfer',
       s.account_id,
       d.account_id,
       round((50000 + b.r_amt * 250000)::numeric, -3),
       'successful',
       date_trunc('second', now() - interval '14 days'
                  + ((b.i - 1) / 20) * interval '1 day'
                  + ((b.i - 1) % 20) * interval '3 minutes')
FROM base b
JOIN stg_active_accounts s ON s.rn = 1 + (b.i - 1) / 20
JOIN stg_active_accounts d ON d.rn = 11 + floor(b.r_dst * (b.cnt - 10))::int;

-- 7. Staging: money movements (the debit and credit legs behind each transaction)
CREATE TEMP TABLE stg_event (
    n             INT,
    leg           INT,
    account_id    BIGINT,
    entry_type    VARCHAR(10),
    amount        NUMERIC(15,2),
    signed_amount NUMERIC(15,2),
    event_time    TIMESTAMPTZ
);

INSERT INTO stg_event
SELECT n, 1, source_account_id, 'debit', amount, -amount, created_at + interval '1 second'
FROM stg_txn
WHERE status IN ('successful', 'reversed') AND source_account_id IS NOT NULL
UNION ALL
SELECT n, 1, destination_account_id, 'credit', amount, amount, created_at + interval '1 second'
FROM stg_txn
WHERE status IN ('successful', 'reversed') AND destination_account_id IS NOT NULL
UNION ALL
SELECT n, 2, source_account_id, 'credit', amount, amount,
       created_at + (60 + r_rev * 1700) * interval '1 second'
FROM stg_txn
WHERE status = 'reversed' AND source_account_id IS NOT NULL
UNION ALL
SELECT n, 2, destination_account_id, 'debit', amount, -amount,
       created_at + (60 + r_rev * 1700) * interval '1 second'
FROM stg_txn
WHERE status = 'reversed' AND destination_account_id IS NOT NULL;

-- 8. Opening deposits (sized so no balance ever drops below zero)
WITH running AS (
    SELECT account_id,
           sum(signed_amount) OVER (PARTITION BY account_id ORDER BY event_time, n, leg) AS run
    FROM stg_event
),
lows AS (
    SELECT account_id, least(0, min(run)) AS low
    FROM running
    GROUP BY account_id
),
opening AS MATERIALIZED (
    SELECT a.account_id, a.opened_at,
           -coalesce(l.low, 0) + round((5000 + power(random(), 2) * 495000)::numeric, -2) AS amount
    FROM accounts a
    LEFT JOIN lows l ON l.account_id = a.account_id
    WHERE a.status <> 'closed'
),
new_txn AS (
    INSERT INTO stg_txn (n, transaction_type, destination_account_id, amount, status, created_at)
    SELECT 200000 + account_id, 'deposit', account_id, amount, 'successful',
           date_trunc('second', opened_at + interval '1 hour')
    FROM opening
    RETURNING n, destination_account_id, amount, created_at
)
INSERT INTO stg_event
SELECT n, 1, destination_account_id, 'credit', amount, amount, created_at + interval '1 second'
FROM new_txn;

-- 9. Transactions (references numbered in time order)
UPDATE stg_txn t
SET reference = 'VGP' || to_char(o.created_at, 'YYYYMMDD') || lpad(o.seq::text, 8, '0')
FROM (SELECT n, created_at, row_number() OVER (ORDER BY created_at, n) AS seq
      FROM stg_txn) o
WHERE o.n = t.n;

INSERT INTO transactions (reference, source_account_id, destination_account_id,
                          transaction_type, amount, status, created_at)
SELECT reference, source_account_id, destination_account_id,
       transaction_type, amount, status, created_at
FROM stg_txn
ORDER BY created_at, n;

-- 10. Transaction logs (running balance worked out per account)
INSERT INTO transaction_logs (transaction_id, account_id, entry_type, amount, balance_after, logged_at)
SELECT t.transaction_id,
       e.account_id,
       e.entry_type,
       e.amount,
       sum(e.signed_amount) OVER (PARTITION BY e.account_id ORDER BY e.event_time, e.n, e.leg),
       e.event_time
FROM stg_event e
JOIN stg_txn s ON s.n = e.n
JOIN transactions t ON t.reference = s.reference
ORDER BY e.event_time, e.n, e.leg;

-- 11. Account balances (credits minus debits from the logs)
UPDATE accounts a
SET balance = l.bal
FROM (SELECT account_id,
             sum(CASE WHEN entry_type = 'credit' THEN amount ELSE -amount END) AS bal
      FROM transaction_logs
      GROUP BY account_id) l
WHERE l.account_id = a.account_id;

-- 12. Beneficiaries (1 to 5 saved recipients per customer)
WITH picks AS MATERIALIZED (
    SELECT c.customer_id, c.created_at AS customer_created_at,
           1 + floor(random() * (SELECT max(account_id) FROM accounts))::int AS pick_account_id,
           random() AS r_nick, random() AS r_name, random() AS r_time
    FROM customers c
    CROSS JOIN LATERAL generate_series(1, 1 + (c.customer_id % 5)) AS k
)
INSERT INTO beneficiaries (customer_id, beneficiary_account_id, nickname, created_at)
SELECT p.customer_id,
       a.account_id,
       CASE WHEN p.r_nick < 0.30 THEN NULL
            ELSE (ARRAY['Mum','Dad','Landlord','Tola','Chidi','Ngozi',
                        'Business partner','School fees','Savings','Rent'])[1 + floor(p.r_name * 10)::int] END,
       p.customer_created_at + p.r_time * (now() - p.customer_created_at)
FROM picks p
JOIN accounts a ON a.account_id = p.pick_account_id
               AND a.customer_id <> p.customer_id
               AND a.status = 'active'
ON CONFLICT (customer_id, beneficiary_account_id) DO NOTHING;

-- 13. Clean up staging tables and refresh planner statistics
DROP TABLE stg_event;
DROP TABLE stg_txn;
DROP TABLE stg_active_accounts;
ANALYZE customers;
ANALYZE accounts;
ANALYZE transactions;
ANALYZE transaction_logs;
ANALYZE beneficiaries;

-- 14. Row counts
SELECT 'customers' AS table_name, count(*) AS row_count FROM customers
UNION ALL SELECT 'accounts', count(*) FROM accounts
UNION ALL SELECT 'transactions', count(*) FROM transactions
UNION ALL SELECT 'transaction_logs', count(*) FROM transaction_logs
UNION ALL SELECT 'beneficiaries', count(*) FROM beneficiaries;
