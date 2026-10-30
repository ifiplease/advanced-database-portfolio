-- 1. Checkpoint and balances before (Tab 1)
SELECT fn_take_test_checkpoint();

SELECT * FROM v_test_account_balances ORDER BY label;

-- 2a. READ COMMITTED: open the transaction and note what account A holds (Tab 1)
BEGIN ISOLATION LEVEL READ COMMITTED;

CREATE TEMP TABLE first_read ON COMMIT DROP AS
SELECT current_setting('transaction_isolation') AS isolation_level,
       balance
FROM accounts
WHERE account_id = fn_test_account('A');

-- 2b. READ COMMITTED: deposit 1000 into account A (Tab 2)
SELECT fn_deposit(fn_test_account('A'), 1000) AS transaction_id;

-- 2c. READ COMMITTED: read account A again in the same transaction (Tab 1)
SELECT f.isolation_level,
       f.balance AS first_read,
       a.balance AS second_read,
       a.balance - f.balance AS change
FROM first_read f
CROSS JOIN accounts a
WHERE a.account_id = fn_test_account('A');

-- 2d. READ COMMITTED: end the transaction (Tab 1)
COMMIT;

-- 3a. REPEATABLE READ: open the transaction and note what account A holds (Tab 1)
BEGIN ISOLATION LEVEL REPEATABLE READ;

CREATE TEMP TABLE first_read ON COMMIT DROP AS
SELECT current_setting('transaction_isolation') AS isolation_level,
       balance
FROM accounts
WHERE account_id = fn_test_account('A');

-- 3b. REPEATABLE READ: deposit 1000 into account A (Tab 2)
SELECT fn_deposit(fn_test_account('A'), 1000) AS transaction_id;

-- 3c. REPEATABLE READ: read account A again in the same transaction (Tab 1)
SELECT f.isolation_level,
       f.balance AS first_read,
       a.balance AS second_read,
       a.balance - f.balance AS change
FROM first_read f
CROSS JOIN accounts a
WHERE a.account_id = fn_test_account('A');

-- 3d. REPEATABLE READ: end the transaction (Tab 1)
COMMIT;

-- 3e. REPEATABLE READ: read account A after the commit (Tab 1)
SELECT current_setting('transaction_isolation') AS isolation_level,
       balance
FROM accounts
WHERE account_id = fn_test_account('A');

-- 4a. Serialization error: open a REPEATABLE READ transaction and read account A (Tab 1)
BEGIN ISOLATION LEVEL REPEATABLE READ;

SELECT current_setting('transaction_isolation') AS isolation_level,
       balance
FROM accounts
WHERE account_id = fn_test_account('A');

-- 4b. Serialization error: deposit 1000 into account A (Tab 2)
SELECT fn_deposit(fn_test_account('A'), 1000) AS transaction_id;

-- 4c. Serialization error: deposit 500 into account A (Tab 1, expected to fail)
SELECT fn_deposit(fn_test_account('A'), 500) AS transaction_id;

-- 4d. Serialization error: roll back the failed transaction (Tab 1)
ROLLBACK;

-- 4e. Retry: run the same deposit in a new transaction (Tab 1)
BEGIN ISOLATION LEVEL REPEATABLE READ;

SELECT fn_deposit(fn_test_account('A'), 500) AS transaction_id;

COMMIT;

-- 4f. Ledger after all deposits (Tab 1)
SELECT * FROM v_test_activity;

-- 5. Stage 3 audit (Tab 1)
SELECT * FROM v_test_account_balances ORDER BY label;

SELECT count(*) AS accounts_checked,
       count(*) FILTER (WHERE stored_balance <> log_balance) AS accounts_out_of_balance
FROM v_balance_audit;
