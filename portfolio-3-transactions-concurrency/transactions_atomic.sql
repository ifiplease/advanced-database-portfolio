-- 1. Reference generator
DROP SEQUENCE IF EXISTS seq_transaction_reference;
CREATE SEQUENCE seq_transaction_reference START 90000001;

CREATE OR REPLACE FUNCTION fn_next_reference()
RETURNS VARCHAR
LANGUAGE sql
AS $$
    SELECT 'VGP' || to_char(now(), 'YYYYMMDD')
           || lpad(nextval('seq_transaction_reference')::text, 8, '0');
$$;

-- 2. Test accounts, helper function and views
DROP TABLE IF EXISTS test_accounts CASCADE;
CREATE TABLE test_accounts (
    label      CHAR(1) NOT NULL,
    account_id BIGINT  NOT NULL,

    CONSTRAINT pk_test_accounts PRIMARY KEY (label),
    CONSTRAINT uq_test_accounts_account UNIQUE (account_id),
    CONSTRAINT fk_test_accounts_account
        FOREIGN KEY (account_id) REFERENCES accounts (account_id)
        ON DELETE RESTRICT
);

INSERT INTO test_accounts (label, account_id)
WITH candidates AS (
    SELECT DISTINCT ON (customer_id) account_id
    FROM accounts
    WHERE status = 'active' AND balance >= 50000
    ORDER BY customer_id, account_id
),
picked AS (
    SELECT account_id, row_number() OVER (ORDER BY account_id) AS rn
    FROM candidates
)
SELECT (ARRAY['A', 'B', 'C'])[rn], account_id
FROM picked
WHERE rn <= 3;

CREATE OR REPLACE FUNCTION fn_test_account(p_label CHAR)
RETURNS BIGINT
LANGUAGE sql
STABLE
AS $$
    SELECT account_id FROM test_accounts WHERE label = p_label;
$$;

CREATE OR REPLACE VIEW v_balance_audit AS
SELECT a.account_id,
       a.balance AS stored_balance,
       COALESCE(l.log_balance, 0) AS log_balance
FROM accounts a
LEFT JOIN (
    SELECT account_id,
           sum(CASE WHEN entry_type = 'credit' THEN amount ELSE -amount END) AS log_balance
    FROM transaction_logs
    GROUP BY account_id
) l ON l.account_id = a.account_id;

CREATE OR REPLACE VIEW v_test_account_balances AS
SELECT t.label,
       t.account_id,
       b.stored_balance,
       b.log_balance,
       b.stored_balance - b.log_balance AS difference
FROM test_accounts t
JOIN v_balance_audit b ON b.account_id = t.account_id;

CREATE OR REPLACE VIEW v_latest_ledger AS
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
WHERE t.transaction_id = (SELECT max(transaction_id) FROM transactions)
ORDER BY l.log_id;

SELECT t.label, a.account_id, a.customer_id, a.account_number, a.balance
FROM test_accounts t
JOIN accounts a ON a.account_id = t.account_id
ORDER BY t.label;

-- 3. Baseline audit
SELECT count(*) AS accounts_checked,
       count(*) FILTER (WHERE stored_balance <> log_balance) AS accounts_out_of_balance
FROM v_balance_audit;

-- 4a. COMMIT: balances before
SELECT * FROM v_test_account_balances ORDER BY label;

-- 4b. COMMIT: deposit of 5,000 into account A
BEGIN;

UPDATE accounts
SET balance = balance + 5000
WHERE account_id = fn_test_account('A');

WITH new_txn AS (
    INSERT INTO transactions (reference, destination_account_id, transaction_type, amount, status)
    VALUES (fn_next_reference(), fn_test_account('A'), 'deposit', 5000, 'successful')
    RETURNING transaction_id
)
INSERT INTO transaction_logs (transaction_id, account_id, entry_type, amount, balance_after)
SELECT n.transaction_id, a.account_id, 'credit', 5000, a.balance
FROM new_txn n
JOIN accounts a ON a.account_id = fn_test_account('A');

COMMIT;

-- 4c. COMMIT: balances after
SELECT * FROM v_test_account_balances ORDER BY label;

-- 5a. ROLLBACK: open the transaction and make the same deposit 
BEGIN;

UPDATE accounts
SET balance = balance + 5000
WHERE account_id = fn_test_account('A');

WITH new_txn AS (
    INSERT INTO transactions (reference, destination_account_id, transaction_type, amount, status)
    VALUES (fn_next_reference(), fn_test_account('A'), 'deposit', 5000, 'successful')
    RETURNING transaction_id
)
INSERT INTO transaction_logs (transaction_id, account_id, entry_type, amount, balance_after)
SELECT n.transaction_id, a.account_id, 'credit', 5000, a.balance
FROM new_txn n
JOIN accounts a ON a.account_id = fn_test_account('A');

-- 5b. ROLLBACK: balances inside the open transaction
SELECT * FROM v_test_account_balances ORDER BY label;

-- 5c. ROLLBACK: undo everything
ROLLBACK;

-- 5d. ROLLBACK: balances after
SELECT * FROM v_test_account_balances ORDER BY label;

-- 6a. Constraint failure: credit account B inside an open transaction
BEGIN;

UPDATE accounts
SET balance = balance + 1000
WHERE account_id = fn_test_account('B');

-- 6b. Constraint failure: balances inside the open transaction
SELECT * FROM v_test_account_balances ORDER BY label;

-- 6c. Constraint failure: debit account A by 1 naira more than its balance
UPDATE accounts
SET balance = balance - (balance + 1)
WHERE account_id = fn_test_account('A');

-- 6d. Constraint failure: any further statement is refused until ROLLBACK
SELECT * FROM v_test_account_balances ORDER BY label;

-- 6e. Constraint failure: undo everything
ROLLBACK;

-- 6f. Constraint failure: balances after (B is back to its earlier value)
SELECT * FROM v_test_account_balances ORDER BY label;

-- 7. Atomic functions
CREATE OR REPLACE FUNCTION fn_deposit(p_account_id BIGINT, p_amount NUMERIC)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_balance NUMERIC(15,2);
    v_txn_id  BIGINT;
BEGIN
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Deposit amount must be greater than zero';
    END IF;

    UPDATE accounts
    SET balance = balance + p_amount
    WHERE account_id = p_account_id AND status = 'active'
    RETURNING balance INTO v_balance;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Deposit refused: account % not found or not active', p_account_id;
    END IF;

    INSERT INTO transactions (reference, destination_account_id, transaction_type, amount, status)
    VALUES (fn_next_reference(), p_account_id, 'deposit', p_amount, 'successful')
    RETURNING transaction_id INTO v_txn_id;

    INSERT INTO transaction_logs (transaction_id, account_id, entry_type, amount, balance_after)
    VALUES (v_txn_id, p_account_id, 'credit', p_amount, v_balance);

    RETURN v_txn_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_withdraw(p_account_id BIGINT, p_amount NUMERIC)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_balance NUMERIC(15,2);
    v_txn_id  BIGINT;
BEGIN
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Withdrawal amount must be greater than zero';
    END IF;

    UPDATE accounts
    SET balance = balance - p_amount
    WHERE account_id = p_account_id
      AND status = 'active'
      AND balance >= p_amount
    RETURNING balance INTO v_balance;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Withdrawal of % refused for account %: not active or insufficient funds',
            p_amount, p_account_id;
    END IF;

    INSERT INTO transactions (reference, source_account_id, transaction_type, amount, status)
    VALUES (fn_next_reference(), p_account_id, 'withdrawal', p_amount, 'successful')
    RETURNING transaction_id INTO v_txn_id;

    INSERT INTO transaction_logs (transaction_id, account_id, entry_type, amount, balance_after)
    VALUES (v_txn_id, p_account_id, 'debit', p_amount, v_balance);

    RETURN v_txn_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_transfer(
    p_source_account_id      BIGINT,
    p_destination_account_id BIGINT,
    p_amount                 NUMERIC
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_source_balance      NUMERIC(15,2);
    v_destination_balance NUMERIC(15,2);
    v_txn_id              BIGINT;
BEGIN
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Transfer amount must be greater than zero';
    END IF;

    IF p_source_account_id = p_destination_account_id THEN
        RAISE EXCEPTION 'Transfer refused: source and destination must be different accounts';
    END IF;

    PERFORM 1
    FROM accounts
    WHERE account_id IN (p_source_account_id, p_destination_account_id)
    ORDER BY account_id
    FOR UPDATE;

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

CREATE OR REPLACE FUNCTION fn_reverse_transaction(p_transaction_id BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_txn     transactions%ROWTYPE;
    v_balance NUMERIC(15,2);
BEGIN
    SELECT * INTO v_txn
    FROM transactions
    WHERE transaction_id = p_transaction_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reversal refused: transaction % not found', p_transaction_id;
    END IF;

    IF v_txn.status <> 'successful' THEN
        RAISE EXCEPTION 'Reversal refused: transaction % has status %, only successful transactions can be reversed',
            p_transaction_id, v_txn.status;
    END IF;

    PERFORM 1
    FROM accounts
    WHERE account_id IN (v_txn.source_account_id, v_txn.destination_account_id)
    ORDER BY account_id
    FOR UPDATE;

    IF v_txn.destination_account_id IS NOT NULL THEN
        UPDATE accounts
        SET balance = balance - v_txn.amount
        WHERE account_id = v_txn.destination_account_id
        RETURNING balance INTO v_balance;

        INSERT INTO transaction_logs (transaction_id, account_id, entry_type, amount, balance_after)
        VALUES (p_transaction_id, v_txn.destination_account_id, 'debit', v_txn.amount, v_balance);
    END IF;

    IF v_txn.source_account_id IS NOT NULL THEN
        UPDATE accounts
        SET balance = balance + v_txn.amount
        WHERE account_id = v_txn.source_account_id
        RETURNING balance INTO v_balance;

        INSERT INTO transaction_logs (transaction_id, account_id, entry_type, amount, balance_after)
        VALUES (p_transaction_id, v_txn.source_account_id, 'credit', v_txn.amount, v_balance);
    END IF;

    UPDATE transactions
    SET status = 'reversed'
    WHERE transaction_id = p_transaction_id;

    RETURN p_transaction_id;
END;
$$;

-- 8a. Deposit 10,000 into account A
SELECT fn_deposit(fn_test_account('A'), 10000) AS transaction_id;
SELECT * FROM v_latest_ledger;

-- 8b. Withdraw 2,500 from account B
SELECT fn_withdraw(fn_test_account('B'), 2500) AS transaction_id;
SELECT * FROM v_latest_ledger;

-- 8c. Withdraw 1 naira more than account C holds 
SELECT fn_withdraw(
    fn_test_account('C'),
    (SELECT balance + 1 FROM accounts WHERE account_id = fn_test_account('C'))
);

-- 8d. Transfer 15,000 from account A to account B
SELECT fn_transfer(fn_test_account('A'), fn_test_account('B'), 15000) AS transaction_id;
SELECT * FROM v_latest_ledger;

-- 8e. Transfer more than account C holds 
SELECT fn_transfer(
    fn_test_account('C'),
    fn_test_account('A'),
    (SELECT balance + 1 FROM accounts WHERE account_id = fn_test_account('C'))
);

-- 8f. Balances after both refusals (account C unchanged)
SELECT * FROM v_test_account_balances ORDER BY label;

-- 8g. Reverse the transfer from 8d
SELECT fn_reverse_transaction((SELECT max(transaction_id) FROM transactions)) AS reversed_transaction_id;
SELECT * FROM v_latest_ledger;

-- 8h. Reverse the same transaction again 
SELECT fn_reverse_transaction((SELECT max(transaction_id) FROM transactions));

-- 9. Stage 1 audit
SELECT * FROM v_test_account_balances ORDER BY label;

SELECT count(*) AS accounts_checked,
       count(*) FILTER (WHERE stored_balance <> log_balance) AS accounts_out_of_balance
FROM v_balance_audit;
