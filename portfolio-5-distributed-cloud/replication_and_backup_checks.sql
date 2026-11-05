-- 1. Replication settings and status of this server
SELECT name AS check_name, setting AS value
FROM pg_settings
WHERE name IN ('wal_level', 'max_wal_senders', 'max_replication_slots',
               'hot_standby', 'archive_mode', 'synchronous_commit',
               'synchronous_standby_names')
UNION ALL SELECT 'server_version', current_setting('server_version')
UNION ALL SELECT 'is_standby', pg_is_in_recovery()::text
UNION ALL SELECT 'current_wal_lsn', pg_current_wal_lsn()::text
UNION ALL SELECT 'current_wal_file', pg_walfile_name(pg_current_wal_lsn())
UNION ALL SELECT 'connected_standbys', (SELECT count(*) FROM pg_stat_replication)::text
UNION ALL SELECT 'replication_slots', (SELECT count(*) FROM pg_replication_slots)::text
ORDER BY check_name;

-- 2. Verification
SELECT current_database() AS database_name,
       v.check_name,
       v.result
FROM (
    SELECT 1 AS sort_order, 'customers' AS check_name, count(*) AS result FROM customers
    UNION ALL SELECT 2, 'accounts', count(*) FROM accounts
    UNION ALL SELECT 3, 'transactions', count(*) FROM transactions
    UNION ALL SELECT 4, 'transaction_logs', count(*) FROM transaction_logs
    UNION ALL SELECT 5, 'beneficiaries', count(*) FROM beneficiaries
    UNION ALL SELECT 6, 'partition_demo_transactions', count(*) FROM partition_demo.transactions
    UNION ALL SELECT 7, 'total_balance_ngn', sum(balance) FROM accounts
    UNION ALL SELECT 8, 'accounts_checked', count(*) FROM v_balance_audit
    UNION ALL SELECT 9, 'accounts_out_of_balance',
                        count(*) FILTER (WHERE stored_balance <> log_balance)
                        FROM v_balance_audit
) v
ORDER BY v.sort_order;
