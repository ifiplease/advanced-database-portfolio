-- Key Operation 7: account statement for one account, July to September 2026
EXPLAIN ANALYZE
SELECT l.logged_at,
       t.reference,
       t.transaction_type,
       l.entry_type,
       l.amount,
       l.balance_after,
       t.status
FROM accounts a
JOIN transaction_logs l ON l.account_id = a.account_id
JOIN transactions t ON t.transaction_id = l.transaction_id
WHERE a.account_number = '3000000025'
  AND l.logged_at >= '2026-07-01'
  AND l.logged_at <  '2026-10-01'
ORDER BY l.logged_at, l.log_id;

-- Key Operation 8: accounts sending 10+ transfers of at least 50,000 within one hour
EXPLAIN ANALYZE
WITH windowed AS (
    SELECT t.source_account_id,
           t.created_at,
           t.amount,
           count(*) OVER w AS transfers_in_last_hour,
           sum(t.amount) OVER w AS amount_in_last_hour
    FROM transactions t
    WHERE t.transaction_type = 'transfer'
      AND t.status = 'successful'
      AND t.amount >= 50000
    WINDOW w AS (PARTITION BY t.source_account_id
                 ORDER BY t.created_at
                 RANGE BETWEEN INTERVAL '1 hour' PRECEDING AND CURRENT ROW)
)
SELECT a.account_number,
       max(w.transfers_in_last_hour) AS most_transfers_in_one_hour,
       max(w.amount_in_last_hour) AS highest_amount_in_one_hour,
       min(w.created_at) AS first_flagged_at
FROM windowed w
JOIN accounts a ON a.account_id = w.source_account_id
WHERE w.transfers_in_last_hour >= 10
GROUP BY a.account_number
ORDER BY most_transfers_in_one_hour DESC, a.account_number;

-- Key Operation 6: accounts where the stored balance differs from the transaction logs
EXPLAIN ANALYZE
SELECT a.account_id,
       a.account_number,
       a.balance AS stored_balance,
       coalesce(sum(CASE WHEN l.entry_type = 'credit' THEN l.amount ELSE -l.amount END), 0) AS calculated_balance
FROM accounts a
LEFT JOIN transaction_logs l ON l.account_id = a.account_id
GROUP BY a.account_id, a.account_number, a.balance
HAVING a.balance <> coalesce(sum(CASE WHEN l.entry_type = 'credit' THEN l.amount ELSE -l.amount END), 0)
ORDER BY a.account_id;
