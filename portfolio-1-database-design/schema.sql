-- MIT 8103 Advanced Database Systems
-- Portfolio 1: Database Design and Modelling (VanguardPay)

DROP TABLE IF EXISTS beneficiaries;
DROP TABLE IF EXISTS transaction_logs;
DROP TABLE IF EXISTS transactions;
DROP TABLE IF EXISTS accounts;
DROP TABLE IF EXISTS customers;

-- 1. Customers
CREATE TABLE customers (
    customer_id   BIGINT GENERATED ALWAYS AS IDENTITY,
    first_name    VARCHAR(50)  NOT NULL,
    last_name     VARCHAR(50)  NOT NULL,
    email         VARCHAR(100) NOT NULL,
    phone_number  VARCHAR(20)  NOT NULL,
    date_of_birth DATE         NOT NULL,
    kyc_status    VARCHAR(20)  NOT NULL DEFAULT 'pending',
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT pk_customers PRIMARY KEY (customer_id),
    CONSTRAINT uq_customers_email UNIQUE (email),
    CONSTRAINT uq_customers_phone_number UNIQUE (phone_number),
    CONSTRAINT ck_customers_kyc_status
        CHECK (kyc_status IN ('pending', 'verified', 'rejected'))
);

-- 2. Accounts
CREATE TABLE accounts (
    account_id     BIGINT GENERATED ALWAYS AS IDENTITY,
    customer_id    BIGINT        NOT NULL,
    account_number VARCHAR(10)   NOT NULL,
    account_type   VARCHAR(20)   NOT NULL,
    balance        NUMERIC(15,2) NOT NULL DEFAULT 0,
    currency       CHAR(3)       NOT NULL DEFAULT 'NGN',
    status         VARCHAR(20)   NOT NULL DEFAULT 'active',
    opened_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),

    CONSTRAINT pk_accounts PRIMARY KEY (account_id),
    CONSTRAINT uq_accounts_account_number UNIQUE (account_number),
    CONSTRAINT fk_accounts_customer
        FOREIGN KEY (customer_id) REFERENCES customers (customer_id)
        ON DELETE RESTRICT,
    CONSTRAINT ck_accounts_account_number_format
        CHECK (account_number ~ '^[0-9]{10}$'),
    CONSTRAINT ck_accounts_account_type
        CHECK (account_type IN ('savings', 'current')),
    CONSTRAINT ck_accounts_balance
        CHECK (balance >= 0),
    CONSTRAINT ck_accounts_status
        CHECK (status IN ('active', 'frozen', 'closed'))
);

-- 3. Transactions
CREATE TABLE transactions (
    transaction_id         BIGINT GENERATED ALWAYS AS IDENTITY,
    reference              VARCHAR(30)   NOT NULL,
    source_account_id      BIGINT,
    destination_account_id BIGINT,
    transaction_type       VARCHAR(20)   NOT NULL,
    amount                 NUMERIC(15,2) NOT NULL,
    status                 VARCHAR(20)   NOT NULL DEFAULT 'pending',
    created_at             TIMESTAMPTZ   NOT NULL DEFAULT now(),

    CONSTRAINT pk_transactions PRIMARY KEY (transaction_id),
    CONSTRAINT uq_transactions_reference UNIQUE (reference),
    CONSTRAINT fk_transactions_source_account
        FOREIGN KEY (source_account_id) REFERENCES accounts (account_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_transactions_destination_account
        FOREIGN KEY (destination_account_id) REFERENCES accounts (account_id)
        ON DELETE RESTRICT,
    CONSTRAINT ck_transactions_type
        CHECK (transaction_type IN ('deposit', 'withdrawal', 'transfer')),
    CONSTRAINT ck_transactions_amount
        CHECK (amount > 0),
    CONSTRAINT ck_transactions_status
        CHECK (status IN ('pending', 'successful', 'failed', 'reversed')),

    -- Enforce valid source/destination combinations per transaction type
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
);

-- 4. Transaction Logs
CREATE TABLE transaction_logs (
    log_id         BIGINT GENERATED ALWAYS AS IDENTITY,
    transaction_id BIGINT        NOT NULL,
    account_id     BIGINT        NOT NULL,
    entry_type     VARCHAR(10)   NOT NULL,
    amount         NUMERIC(15,2) NOT NULL,
    balance_after  NUMERIC(15,2) NOT NULL,
    logged_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),

    CONSTRAINT pk_transaction_logs PRIMARY KEY (log_id),
    CONSTRAINT fk_transaction_logs_transaction
        FOREIGN KEY (transaction_id) REFERENCES transactions (transaction_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_transaction_logs_account
        FOREIGN KEY (account_id) REFERENCES accounts (account_id)
        ON DELETE RESTRICT,
    CONSTRAINT ck_transaction_logs_entry_type
        CHECK (entry_type IN ('debit', 'credit')),
    CONSTRAINT ck_transaction_logs_amount
        CHECK (amount > 0),
    CONSTRAINT ck_transaction_logs_balance_after
        CHECK (balance_after >= 0)
);

-- 5. Beneficiaries
CREATE TABLE beneficiaries (
    beneficiary_id         BIGINT GENERATED ALWAYS AS IDENTITY,
    customer_id            BIGINT      NOT NULL,
    beneficiary_account_id BIGINT      NOT NULL,
    nickname               VARCHAR(50),
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT pk_beneficiaries PRIMARY KEY (beneficiary_id),
    CONSTRAINT fk_beneficiaries_customer
        FOREIGN KEY (customer_id) REFERENCES customers (customer_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_beneficiaries_account
        FOREIGN KEY (beneficiary_account_id) REFERENCES accounts (account_id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_beneficiaries_customer_account
        UNIQUE (customer_id, beneficiary_account_id)
);
