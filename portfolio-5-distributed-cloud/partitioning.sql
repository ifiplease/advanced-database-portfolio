-- 1. Date range of the live ledger
SELECT min(created_at) AS earliest,
       max(created_at) AS latest,
       count(*)        AS row_count
FROM public.transactions;

-- 2. Fresh schema for the partitioned copy
DROP SCHEMA IF EXISTS partition_demo CASCADE;
CREATE SCHEMA partition_demo;

-- 3. Partitioned parent table
CREATE TABLE partition_demo.transactions (
    transaction_id         BIGINT        NOT NULL,
    reference              VARCHAR(30)   NOT NULL,
    source_account_id      BIGINT,
    destination_account_id BIGINT,
    transaction_type       VARCHAR(20)   NOT NULL,
    amount                 NUMERIC(15,2) NOT NULL,
    status                 VARCHAR(20)   NOT NULL DEFAULT 'pending',
    created_at             TIMESTAMPTZ   NOT NULL DEFAULT now(),

    CONSTRAINT pk_transactions_partitioned PRIMARY KEY (transaction_id, created_at),
    CONSTRAINT fk_transactions_source_account
        FOREIGN KEY (source_account_id) REFERENCES public.accounts (account_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_transactions_destination_account
        FOREIGN KEY (destination_account_id) REFERENCES public.accounts (account_id)
        ON DELETE RESTRICT,
    CONSTRAINT ck_transactions_type
        CHECK (transaction_type IN ('deposit', 'withdrawal', 'transfer')),
    CONSTRAINT ck_transactions_amount
        CHECK (amount > 0),
    CONSTRAINT ck_transactions_status
        CHECK (status IN ('pending', 'successful', 'failed', 'reversed')),
    CONSTRAINT ck_transactions_type_accounts
        CHECK (
            (transaction_type = 'deposit'
                AND source_account_id IS NULL
                AND destination_account_id IS NOT NULL)
         OR (transaction_type = 'withdrawal'
                AND source_account_id IS NOT NULL
                AND destination_account_id IS NULL)
         OR (transaction_type = 'transfer'
                AND source_account_id IS NOT NULL
                AND destination_account_id IS NOT NULL
                AND source_account_id <> destination_account_id)
        )
) PARTITION BY RANGE (created_at);

-- 4. Monthly partitions, built from the dates in the live ledger
DO $$
DECLARE
    v_month DATE;
    v_last  DATE;
BEGIN
    SELECT date_trunc('month', min(created_at))::date,
           date_trunc('month', greatest(max(created_at), now()))::date
    INTO v_month, v_last
    FROM public.transactions;

    WHILE v_month <= v_last LOOP
        EXECUTE format(
            'CREATE TABLE partition_demo.%I PARTITION OF partition_demo.transactions
             FOR VALUES FROM (%L) TO (%L)',
            'transactions_' || to_char(v_month, 'YYYY_MM'),
            v_month::timestamptz,
            (v_month + interval '1 month')::timestamptz
        );
        v_month := (v_month + interval '1 month')::date;
    END LOOP;
END $$;

-- 5. Default partition for any date outside the monthly ranges
CREATE TABLE partition_demo.transactions_default
    PARTITION OF partition_demo.transactions DEFAULT;

-- 6. Load every row from the live ledger
INSERT INTO partition_demo.transactions
    (transaction_id, reference, source_account_id, destination_account_id,
     transaction_type, amount, status, created_at)
SELECT transaction_id, reference, source_account_id, destination_account_id,
       transaction_type, amount, status, created_at
FROM public.transactions
ORDER BY transaction_id;

-- 7. Refresh planner statistics
ANALYZE partition_demo.transactions;

-- 8. Row count and total amount check
SELECT (SELECT count(*) FROM public.transactions)                  AS original_rows,
       (SELECT count(*) FROM partition_demo.transactions)          AS partitioned_rows,
       (SELECT count(*) FROM partition_demo.transactions_default)  AS default_partition_rows,
       (SELECT sum(amount) FROM public.transactions)               AS original_total,
       (SELECT sum(amount) FROM partition_demo.transactions)       AS partitioned_total;

-- 9. Partition list with bounds and row counts
SELECT c.relname                          AS partition_name,
       pg_get_expr(c.relpartbound, c.oid) AS bounds,
       coalesce(n.row_count, 0)           AS row_count
FROM pg_inherits i
JOIN pg_class c ON c.oid = i.inhrelid
LEFT JOIN (
    SELECT tableoid, count(*) AS row_count
    FROM partition_demo.transactions
    GROUP BY tableoid
) n ON n.tableoid = c.oid
WHERE i.inhparent = 'partition_demo.transactions'::regclass
ORDER BY c.relname;

-- 10. Pruning: one month (only one partition should appear in the plan)
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(amount)
FROM partition_demo.transactions
WHERE created_at >= '2026-10-01'
  AND created_at <  '2026-11-01';

-- 11. No pruning: no date filter (every partition appears in the plan)
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(amount)
FROM partition_demo.transactions;
