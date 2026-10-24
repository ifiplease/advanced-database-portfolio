-- 1. Key Operation 7: account statement lookups by account and date range
CREATE INDEX idx_transaction_logs_account_logged_at
    ON transaction_logs (account_id, logged_at);

-- 2. Key Operation 8: large successful transfers, ordered by sender and time
CREATE INDEX idx_transactions_large_transfers
    ON transactions (source_account_id, created_at)
    INCLUDE (amount)
    WHERE transaction_type = 'transfer'
      AND status = 'successful'
      AND amount >= 50000;

-- 3. Refresh planner statistics (steps 1 to 3 run together)
ANALYZE transaction_logs;
ANALYZE transactions;

-- 4. Ran this on its own, after step 3 (VACUUM cannot run inside a multi-statement script)
VACUUM ANALYZE transactions;
