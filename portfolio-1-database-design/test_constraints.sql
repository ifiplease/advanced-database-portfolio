-- VanguardPay: test_constraints.sql

-- Customers
INSERT INTO customers (first_name, last_name, email, phone_number, date_of_birth, kyc_status)
VALUES
    ('Ada',    'Obi',    'ada.obi@mail.com',      '08031234567', '1995-03-14', 'verified'),
    ('Chidi',  'Okafor', 'chidi.okafor@mail.com', '08059876543', '1992-07-21', 'verified'),
    ('Ngozi',  'Eze',    'ngozi.eze@mail.com',    '07012345678', '1998-11-02', 'pending');

-- Accounts (balances reflect the transactions below)
INSERT INTO accounts (customer_id, account_number, account_type, balance)
VALUES
    ((SELECT customer_id FROM customers WHERE email = 'ada.obi@mail.com'),      '0123456789', 'savings', 45000.00),
    ((SELECT customer_id FROM customers WHERE email = 'chidi.okafor@mail.com'), '0222222222', 'current',  5000.00),
    ((SELECT customer_id FROM customers WHERE email = 'ngozi.eze@mail.com'),    '0333333333', 'savings',     0.00);

-- Transactions: a deposit and a transfer
INSERT INTO transactions (reference, source_account_id, destination_account_id, transaction_type, amount, status)
VALUES
    ('TXN-20261020-0001',
     NULL,
     (SELECT account_id FROM accounts WHERE account_number = '0123456789'),
     'deposit', 50000.00, 'successful'),
    ('TXN-20261020-0002',
     (SELECT account_id FROM accounts WHERE account_number = '0123456789'),
     (SELECT account_id FROM accounts WHERE account_number = '0222222222'),
     'transfer', 5000.00, 'successful');

-- Transaction logs
INSERT INTO transaction_logs (transaction_id, account_id, entry_type, amount, balance_after)
VALUES
    ((SELECT transaction_id FROM transactions WHERE reference = 'TXN-20261020-0001'),
     (SELECT account_id FROM accounts WHERE account_number = '0123456789'),
     'credit', 50000.00, 50000.00),
    ((SELECT transaction_id FROM transactions WHERE reference = 'TXN-20261020-0002'),
     (SELECT account_id FROM accounts WHERE account_number = '0123456789'),
     'debit', 5000.00, 45000.00),
    ((SELECT transaction_id FROM transactions WHERE reference = 'TXN-20261020-0002'),
     (SELECT account_id FROM accounts WHERE account_number = '0222222222'),
     'credit', 5000.00, 5000.00);

-- Beneficiary: Ada saves Chidi
INSERT INTO beneficiaries (customer_id, beneficiary_account_id, nickname)
VALUES
    ((SELECT customer_id FROM customers WHERE email = 'ada.obi@mail.com'),
     (SELECT account_id FROM accounts WHERE account_number = '0222222222'),
     'Chidi');

-- View customers and their accounts
SELECT
    c.customer_id,
    c.first_name || ' ' || c.last_name AS customer_name,
    c.kyc_status,
    a.account_number,
    a.account_type,
    a.balance,
    a.currency,
    a.status
FROM customers c
JOIN accounts a ON a.customer_id = c.customer_id
ORDER BY c.customer_id;


-- Constraint test 1: negative balance (should fail: ck_accounts_balance)
-- INSERT INTO accounts (customer_id, account_number, account_type, balance)
-- VALUES (
--     (SELECT customer_id FROM customers WHERE email = 'ngozi.eze@mail.com'),
--     '0444444444', 'savings', -100.00
-- );

-- Constraint test 2: transfer to the same account (should fail: ck_transactions_type_accounts)
-- INSERT INTO transactions (reference, source_account_id, destination_account_id, transaction_type, amount)
-- VALUES (
--     'TXN-20261020-9999',
--     (SELECT account_id FROM accounts WHERE account_number = '0123456789'),
--     (SELECT account_id FROM accounts WHERE account_number = '0123456789'),
--     'transfer', 1000.00
-- );
