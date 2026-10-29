-- 1. Checkpoint, reset and activity view (Tab 1)
DROP VIEW IF EXISTS v_test_activity;
DROP TABLE IF EXISTS test_checkpoint;

CREATE TABLE test_checkpoint (
    label               CHAR(1)       NOT NULL,
    balance             NUMERIC(15,2) NOT NULL,
    last_transaction_id BIGINT        NOT NULL,
    last_log_id         BIGINT        NOT NULL,

    CONSTRAINT pk_test_checkpoint PRIMARY KEY (label),
    CONSTRAINT fk_test_checkpoint_label
        FOREIGN KEY (label) REFERENCES test_accounts (label)
        ON DELETE RESTRICT
);

CREATE OR REPLACE FUNCTION fn_take_test_checkpoint()
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM test_checkpoint;

    INSERT INTO test_checkpoint (label, balance, last_transaction_id, last_log_id)
    SELECT t.label,
           a.balance,
           (SELECT max(transaction_id) FROM transactions),
           (SELECT max(log_id) FROM transaction_logs)
    FROM test_accounts t
    JOIN accounts a ON a.account_id = t.account_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_reset_to_checkpoint()
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM transaction_logs
    WHERE log_id > (SELECT max(last_log_id) FROM test_checkpoint);

    DELETE FROM transactions
    WHERE transaction_id > (SELECT max(last_transaction_id) FROM test_checkpoint);

    UPDATE accounts a
    SET balance = c.balance
    FROM test_checkpoint c
    JOIN test_accounts t ON t.label = c.label
    WHERE a.account_id = t.account_id;
END;
$$;

CREATE OR REPLACE VIEW v_test_activity AS
SELECT t.transaction_id,
       t.reference,
       t.transaction_type,
       t.amount,
       t.status,
       l.log_id,
       l.account_id,
       l.entry_type,
       l.balance_after
FROM transactions t
JOIN transaction_logs l ON l.transaction_id = t.transaction_id
WHERE t.transaction_id > (SELECT max(last_transaction_id) FROM test_checkpoint)
ORDER BY t.transaction_id, l.log_id;

SELECT fn_take_test_checkpoint();

SELECT * FROM v_test_account_balances ORDER BY label;

-- 2. Concurrency functions (Tab 1)
CREATE OR REPLACE FUNCTION fn_withdraw_no_lock(
    p_account_id BIGINT,
    p_amount     NUMERIC,
    p_delay      INT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_balance     NUMERIC(15,2);
    v_new_balance NUMERIC(15,2);
    v_txn_id      BIGINT;
BEGIN
    SELECT balance INTO v_balance
    FROM accounts
    WHERE account_id = p_account_id;

    IF v_balance < p_amount THEN
        RAISE EXCEPTION 'Withdrawal of % refused: balance is only %', p_amount, v_balance;
    END IF;

    PERFORM pg_sleep(p_delay);

    v_new_balance := v_balance - p_amount;

    UPDATE accounts
    SET balance = v_new_balance
    WHERE account_id = p_account_id;

    INSERT INTO transactions (reference, source_account_id, transaction_type, amount, status)
    VALUES (fn_next_reference(), p_account_id, 'withdrawal', p_amount, 'successful')
    RETURNING transaction_id INTO v_txn_id;

    INSERT INTO transaction_logs (transaction_id, account_id, entry_type, amount, balance_after)
    VALUES (v_txn_id, p_account_id, 'debit', p_amount, v_new_balance);

    RETURN v_txn_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_withdraw_locked(
    p_account_id BIGINT,
    p_amount     NUMERIC,
    p_delay      INT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_balance     NUMERIC(15,2);
    v_new_balance NUMERIC(15,2);
    v_txn_id      BIGINT;
BEGIN
    SELECT balance INTO v_balance
    FROM accounts
    WHERE account_id = p_account_id
    FOR UPDATE;

    IF v_balance < p_amount THEN
        RAISE EXCEPTION 'Withdrawal of % refused: balance is only %', p_amount, v_balance;
    END IF;

    PERFORM pg_sleep(p_delay);

    v_new_balance := v_balance - p_amount;

    UPDATE accounts
    SET balance = v_new_balance
    WHERE account_id = p_account_id;

    INSERT INTO transactions (reference, source_account_id, transaction_type, amount, status)
    VALUES (fn_next_reference(), p_account_id, 'withdrawal', p_amount, 'successful')
    RETURNING transaction_id INTO v_txn_id;

    INSERT INTO transaction_logs (transaction_id, account_id, entry_type, amount, balance_after)
    VALUES (v_txn_id, p_account_id, 'debit', p_amount, v_new_balance);

    RETURN v_txn_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_transfer_demo(
    p_source_account_id      BIGINT,
    p_destination_account_id BIGINT,
    p_amount                 NUMERIC,
    p_delay                  INT,
    p_ordered                BOOLEAN
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_first               BIGINT;
    v_second              BIGINT;
    v_source_balance      NUMERIC(15,2);
    v_destination_balance NUMERIC(15,2);
    v_txn_id              BIGINT;
BEGIN
    IF p_ordered THEN
        v_first  := least(p_source_account_id, p_destination_account_id);
        v_second := greatest(p_source_account_id, p_destination_account_id);
    ELSE
        v_first  := p_source_account_id;
        v_second := p_destination_account_id;
    END IF;

    PERFORM 1 FROM accounts WHERE account_id = v_first FOR UPDATE;
    PERFORM pg_sleep(p_delay);
    PERFORM 1 FROM accounts WHERE account_id = v_second FOR UPDATE;

    UPDATE accounts
    SET balance = balance - p_amount
    WHERE account_id = p_source_account_id
      AND status = 'active'
      AND balance >= p_amount
    RETURNING balance INTO v_source_balance;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Transfer of % refused: source account % is not active or has insufficient funds',
            p_amount, p_source_account_id;
    END IF;

    UPDATE accounts
    SET balance = balance + p_amount
    WHERE account_id = p_destination_account_id AND status = 'active'
    RETURNING balance INTO v_destination_balance;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Transfer refused: destination account % not found or not active',
            p_destination_account_id;
    END IF;

    INSERT INTO transactions (reference, source_account_id, destination_account_id,
                              transaction_type, amount, status)
    VALUES (fn_next_reference(), p_source_account_id, p_destination_account_id,
            'transfer', p_amount, 'successful')
    RETURNING transaction_id INTO v_txn_id;

    INSERT INTO transaction_logs (transaction_id, account_id, entry_type, amount, balance_after)
    VALUES (v_txn_id, p_source_account_id,      'debit',  p_amount, v_source_balance),
           (v_txn_id, p_destination_account_id, 'credit', p_amount, v_destination_balance);

    RETURN v_txn_id;
END;
$$;

-- 3a. No locking: balances before (Tab 1)
SELECT * FROM v_test_account_balances ORDER BY label;

-- 3b. No locking: withdrawal 1 of 60% of account C (Tab 1, first)
SELECT fn_withdraw_no_lock(
    fn_test_account('C'),
    (SELECT round(balance * 0.6, 2) FROM accounts WHERE account_id = fn_test_account('C')),
    30
) AS transaction_id;

-- 3c. No locking: withdrawal 2 of 60% of account C (Tab 2, within 30 seconds of 3b)
SELECT fn_withdraw_no_lock(
    fn_test_account('C'),
    (SELECT round(balance * 0.6, 2) FROM accounts WHERE account_id = fn_test_account('C')),
    30
) AS transaction_id;

-- 3d. No locking: both withdrawals in the ledger (Tab 1, )
SELECT * FROM v_test_activity;

-- 3e. No locking: audit after both withdrawals (Tab 1)
SELECT * FROM v_test_account_balances ORDER BY label;

-- 4a. Locking: reset to the checkpoint and check the balances (Tab 1)
SELECT fn_reset_to_checkpoint();

SELECT * FROM v_test_account_balances ORDER BY label;

-- 4b. Locking: withdrawal 1 of 60% of account C (Tab 1, run first)
SELECT fn_withdraw_locked(
    fn_test_account('C'),
    (SELECT round(balance * 0.6, 2) FROM accounts WHERE account_id = fn_test_account('C')),
    30
) AS transaction_id;

-- 4c. Locking: withdrawal 2 of 60% of account C (Tab 2, within 30 seconds of 4b)
SELECT fn_withdraw_locked(
    fn_test_account('C'),
    (SELECT round(balance * 0.6, 2) FROM accounts WHERE account_id = fn_test_account('C')),
    30
) AS transaction_id;

-- 4d. Locking: ledger after both calls (Tab 1)
SELECT * FROM v_test_activity;

-- 4e. Locking: audit after both calls (Tab 1)
SELECT * FROM v_test_account_balances ORDER BY label;

-- 4f. Optional: who is waiting on a lock (Tab 3, while 4c is still running)
SELECT pid, state, wait_event_type, wait_event, left(query, 70) AS query
FROM pg_stat_activity
WHERE datname = current_database()
  AND state = 'active'
  AND pid <> pg_backend_pid();

-- 5a. Deadlock: new checkpoint and balances before (Tab 1)
SELECT fn_take_test_checkpoint();

SELECT * FROM v_test_account_balances ORDER BY label;

-- 5b. Deadlock: transfer 1000 from A to B, locking A first (Tab 1, first)
SELECT fn_transfer_demo(fn_test_account('A'), fn_test_account('B'), 1000, 30, false) AS transaction_id;

-- 5c. Deadlock: transfer 2000 from B to A, locking B first (Tab 2, within 30 seconds of 5b)
SELECT fn_transfer_demo(fn_test_account('B'), fn_test_account('A'), 2000, 30, false) AS transaction_id;

-- 5d. Deadlock: ledger after one transfer was cancelled (Tab 1)
SELECT * FROM v_test_activity;

SELECT * FROM v_test_account_balances ORDER BY label;

-- 6a. Prevention: new checkpoint and balances before (Tab 1)
SELECT fn_take_test_checkpoint();

SELECT * FROM v_test_account_balances ORDER BY label;

-- 6b. Prevention: transfer 1500 from A to B, locking the lower account_id first (Tab 1)
SELECT fn_transfer_demo(fn_test_account('A'), fn_test_account('B'), 1500, 30, true) AS transaction_id;

-- 6c. Prevention: transfer 2500 from B to A, locking the lower account_id first (Tab 2, within 30 seconds of 6b)
SELECT fn_transfer_demo(fn_test_account('B'), fn_test_account('A'), 2500, 30, true) AS transaction_id;

-- 6d. Prevention: ledger after both transfers (Tab 1)
SELECT * FROM v_test_activity;

-- 6e. Stage 2 audit (Tab 1)
SELECT * FROM v_test_account_balances ORDER BY label;

SELECT count(*) AS accounts_checked,
       count(*) FILTER (WHERE stored_balance <> log_balance) AS accounts_out_of_balance
FROM v_balance_audit;
