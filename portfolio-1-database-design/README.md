# Portfolio 1: Database Design and Modelling

This folder covers the relational design for the VanguardPay case study. It contains the case study description, the ER diagram, the relational schema, keys, constraints, and the normalisation explanation. The database is built in PostgreSQL and managed with pgAdmin 4.

---

## Selected Case Study: VanguardPay

### Organisation

VanguardPay is a simulated fintech company based in Nigeria. 

### Nature of the Business / System

VanguardPay is a digital banking and payments platform. Customers sign up through a mobile app or website, open accounts, and move money without visiting a physical branch. The platform lets customers hold balances, send money to other accounts, deposit and withdraw funds, and view their transaction history. Because VanguardPay handles real money, the database must be accurate, secure, and fully auditable. Every naira that moves must be recorded and traceable.

### Users of the Database

- **Customers:** use the app to check balances, make transfers, and view statements.
- **Customer support agents:** look up customer accounts and transactions to resolve complaints.
- **Compliance and audit officers:** review transaction logs and check that account balances are correct.
- **Fraud analysts:** monitor transactions and audit logs for suspicious behaviour.
- **Database administrators:** manage the database, backups, performance, and access control.
- **The VanguardPay application backend:** reads and writes data automatically on behalf of customers.

### Major Data to be Stored

- **Customers:** personal details, contact information, and identity verification (KYC) status.
- **Accounts:** account numbers, account types (e.g. savings, current), balances, currency, and account status.
- **Transactions:** transfers, deposits, and withdrawals, with amounts, timestamps, and status (pending, successful, failed, reversed).
- **Transaction logs:** a permanent audit record of every change to money in the system.
- **Beneficiaries:** saved recipients that customers send money to often.

### Key Operations the Database Will Support

1. **Register a customer and open an account.**
2. **Deposit funds** into an account.
3. **Withdraw funds** from an account, blocking the request if the balance is too low.
4. **Transfer funds** between two accounts safely, so that money is never lost or duplicated.
5. **Reverse failed transactions** and put the money back correctly.
6. **Audit account balances** by comparing stored balances against the transaction history.
7. **Generate account statements** for a chosen customer and date range.
8. **Identify suspicious activity** by querying transactions, such as unusually large or very frequent transfers.

---

## ER Diagram, Relational Schema, Keys, and Constraints

### ER Diagram

I designed the VanguardPay database with 5 tables. The ER diagram below shows how they connect. I drew it in dbdiagram.io.

![VanguardPay ER Diagram](er-diagram.png)

### Relationships

| Relationship | Cardinality | Explanation |
|---|---|---|
| `customers` → `accounts` | One-to-many | One customer can own many accounts. Each account belongs to one customer. |
| `customers` → `beneficiaries` | One-to-many | One customer can save many recipients. |
| `accounts` → `beneficiaries` | One-to-many | One account can be saved as a recipient by many customers. |
| `accounts` → `transactions` (source) | One-to-many | One account can send money in many transactions. |
| `accounts` → `transactions` (destination) | One-to-many | One account can receive money in many transactions. |
| `transactions` → `transaction_logs` | One-to-many | One transaction creates one or more log entries. A transfer creates two (a debit and a credit). |
| `accounts` → `transaction_logs` | One-to-many | One account can have many log entries, which I use to audit its balance. |

Deposits have no source account and withdrawals have no destination account, so those two columns in `transactions` are allowed to be empty depending on the transaction type.

### Relational Schema

Primary keys are underlined with `PK` and foreign keys are marked `FK`.

- **customers** (customer_id `PK`, first_name, last_name, email, phone_number, date_of_birth, kyc_status, created_at)
- **accounts** (account_id `PK`, customer_id `FK`, account_number, account_type, balance, currency, status, opened_at)
- **transactions** (transaction_id `PK`, reference, source_account_id `FK`, destination_account_id `FK`, transaction_type, amount, status, created_at)
- **transaction_logs** (log_id `PK`, transaction_id `FK`, account_id `FK`, entry_type, amount, balance_after, logged_at)
- **beneficiaries** (beneficiary_id `PK`, customer_id `FK`, beneficiary_account_id `FK`, nickname, created_at)

### Keys

| Table | Primary Key | Foreign Keys | Unique Keys |
|---|---|---|---|
| `customers` | `customer_id` | None | `email`, `phone_number` |
| `accounts` | `account_id` | `customer_id` → `customers` | `account_number` |
| `transactions` | `transaction_id` | `source_account_id` → `accounts`, `destination_account_id` → `accounts` | `reference` |
| `transaction_logs` | `log_id` | `transaction_id` → `transactions`, `account_id` → `accounts` | None |
| `beneficiaries` | `beneficiary_id` | `customer_id` → `customers`, `beneficiary_account_id` → `accounts` | (`customer_id`, `beneficiary_account_id`) together |

All foreign keys use `ON DELETE RESTRICT`. This means a customer or account cannot be deleted while other records still depend on it. I chose this because financial records should never disappear.

### Constraints

| Table | Constraint | Purpose |
|---|---|---|
| `customers` | `kyc_status` must be `pending`, `verified`, or `rejected` | Only valid identity statuses are allowed. |
| `customers` | `email` and `phone_number` must be unique | No two customers can share contact details. |
| `accounts` | `balance >= 0` | An account balance can never go negative. |
| `accounts` | `account_type` must be `savings` or `current` | Only valid account types are allowed. |
| `accounts` | `status` must be `active`, `frozen`, or `closed` | Only valid account statuses are allowed. |
| `accounts` | `account_number` must be exactly 10 digits | Keeps account numbers in a valid format. |
| `transactions` | `amount > 0` | A transaction cannot be zero or negative. |
| `transactions` | `transaction_type` must be `deposit`, `withdrawal`, or `transfer` | Only valid transaction types are allowed. |
| `transactions` | `status` must be `pending`, `successful`, `failed`, or `reversed` | Only valid statuses are allowed. |
| `transactions` | Deposit needs a destination only, withdrawal needs a source only, transfer needs both and they must be different | Stops a transaction from having the wrong accounts for its type. |
| `transaction_logs` | `entry_type` must be `debit` or `credit` | Every log entry must be one or the other. |
| `transaction_logs` | `amount > 0` and `balance_after >= 0` | Log entries must show valid money values. |
| All tables | `NOT NULL` on required columns | Important fields can never be left empty. |
